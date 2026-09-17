import Foundation

public struct SchoolSoftCredentials: Sendable {
    public var schoolURL: String
    public var username: String
    public var password: String

    public init(schoolURL: String, username: String, password: String) {
        self.schoolURL = schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    /// Normalizes the school URL. This MUST include the school's own path
    /// segment, not just the bare SchoolSoft domain — e.g.
    /// "https://sms.schoolsoft.se/rytmus", not "https://sms.schoolsoft.se".
    public var normalizedURL: URL? {
        var str = schoolURL
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        while str.hasSuffix("/") {
            str.removeLast()
        }
        return URL(string: str)
    }
}

public enum SchoolSoftServiceError: LocalizedError, Sendable {
    case notConfigured
    case invalidURL
    case authenticationFailed(String)
    case ssoRequired(String)
    case networkError(String)
    case parsingError(String)
    case noOrganizationFound

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Please enter your school URL, username, and password."
        case .invalidURL:
            return "The school URL provided is invalid. Include the school segment, e.g. https://sms.schoolsoft.se/rytmus."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .ssoRequired(let school):
            return "\(school) returned a login page instead of API data. Double-check the School URL includes your school's path segment (e.g. /rytmus), and that \"Åtkomst från app\" is enabled on your SchoolSoft profile."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Could not parse schedule: \(message)"
        case .noOrganizationFound:
            return "Login succeeded but SchoolSoft did not return a student/organization for this account."
        }
    }
}

public protocol SchoolSoftScheduleService: Sendable {
    func fetchSchedule(using credentials: SchoolSoftCredentials) async throws -> Schedule
    func fetchLunchMenu(using credentials: SchoolSoftCredentials) async throws -> LunchMenu
}

/// Live SchoolSoft client that communicates with the SchoolSoft mobile API endpoints.
///
/// Login, token exchange, and both the `/api/lessons/student/{orgId}` and
/// `/api/lunchmenus/student/{orgId}` endpoints have been confirmed against a
/// real account (Rytmus, via `sms.schoolsoft.se`) — the three-step
/// login -> token -> fetch flow works. The DTOs below decode the actual
/// field names observed in that live response, captured via the `#if DEBUG`
/// console prints in `retrieveLessons` / `retrieveLunch`.
public final class SchoolSoftClient: SchoolSoftScheduleService {
    private let urlSession: URLSession
    private let appVersion = "2.3.2"
    private let appOS = "ios"

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func fetchSchedule(using credentials: SchoolSoftCredentials) async throws -> Schedule {
        let session = try await authenticate(using: credentials)
        return try await retrieveLessons(baseURL: session.baseURL, token: session.token, orgId: session.orgId)
    }

    public func fetchLunchMenu(using credentials: SchoolSoftCredentials) async throws -> LunchMenu {
        let session = try await authenticate(using: credentials)
        return try await retrieveLunch(baseURL: session.baseURL, token: session.token, orgId: session.orgId)
    }

    // MARK: - Shared login + token exchange

    private struct AuthSession {
        var baseURL: URL
        var token: String
        var orgId: Int
    }

    private func authenticate(using credentials: SchoolSoftCredentials) async throws -> AuthSession {
        guard let baseURL = credentials.normalizedURL else {
            throw SchoolSoftServiceError.invalidURL
        }

        guard !credentials.username.isEmpty && !credentials.password.isEmpty else {
            throw SchoolSoftServiceError.notConfigured
        }

        let loginResponse = try await login(baseURL: baseURL, credentials: credentials)
        guard let org = loginResponse.orgs.first else {
            throw SchoolSoftServiceError.noOrganizationFound
        }

        let token = try await fetchToken(baseURL: baseURL, appKey: loginResponse.appKey)

        return AuthSession(baseURL: baseURL, token: token, orgId: org.orgId)
    }

    private func login(baseURL: URL, credentials: SchoolSoftCredentials) async throws -> LoginResponse {
        let loginURL = baseURL.appendingPathComponent("rest/app/login")

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appVersion, forHTTPHeaderField: "appversion")
        request.setValue(appOS, forHTTPHeaderField: "appos")

        request.httpBody = Self.formEncode([
            "identification": credentials.username,
            "verification": credentials.password,
            "logintype": "4",
            "usertype": "1"
        ])

        let (data, response) = try await perform(request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw SchoolSoftServiceError.authenticationFailed("Incorrect username or password.")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                if let str = String(data: data, encoding: .utf8), str.contains("<!DOCTYPE") || str.contains("<html") {
                    throw SchoolSoftServiceError.ssoRequired(baseURL.host ?? "Your school")
                }
                throw SchoolSoftServiceError.authenticationFailed("Server returned status code \(httpResponse.statusCode).")
            }
        }

        do {
            return try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch {
            throw SchoolSoftServiceError.parsingError("Unexpected login response (\(error.localizedDescription)).")
        }
    }

    private func fetchToken(baseURL: URL, appKey: String) async throws -> String {
        let tokenURL = baseURL.appendingPathComponent("rest/app/token")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "GET"
        request.setValue(appKey, forHTTPHeaderField: "appkey")
        request.setValue(appVersion, forHTTPHeaderField: "appversion")
        request.setValue(appOS, forHTTPHeaderField: "appos")
        request.setValue("", forHTTPHeaderField: "deviceid")

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SchoolSoftServiceError.authenticationFailed("Could not obtain a session token (the app key may have been rejected).")
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data).token
        } catch {
            throw SchoolSoftServiceError.parsingError("Unexpected token response (\(error.localizedDescription)).")
        }
    }

    // MARK: - Lessons

    private func retrieveLessons(baseURL: URL, token: String, orgId: Int) async throws -> Schedule {
        let scheduleURL = baseURL.appendingPathComponent("api/lessons/student/\(orgId)")

        var request = URLRequest(url: scheduleURL)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue(appVersion, forHTTPHeaderField: "appversion")
        request.setValue(appOS, forHTTPHeaderField: "appos")

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SchoolSoftServiceError.networkError("Failed to fetch schedule from SchoolSoft (status \(status)).")
        }

        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("SchoolSoft /api/lessons raw response:\n\(raw)")
        }
        #endif

        do {
            let dtoLessons = try JSONDecoder().decode([LessonDTO].self, from: data)

            var weekCalendar = Calendar(identifier: .iso8601)
            weekCalendar.timeZone = .current
            let today = Date()
            let weekOfYear = weekCalendar.component(.weekOfYear, from: today)
            guard let weekStart = weekCalendar.dateInterval(of: .weekOfYear, for: today)?.start else {
                throw SchoolSoftServiceError.parsingError("Could not determine the current week.")
            }

            let lessons = dtoLessons.compactMap {
                $0.lesson(forWeek: weekOfYear, weekStart: weekStart, calendar: weekCalendar)
            }
            return Schedule(lessons: lessons, lastUpdated: .now)
        } catch let error as SchoolSoftServiceError {
            throw error
        } catch {
            throw SchoolSoftServiceError.parsingError(
                "Lessons format unexpected (\(error.localizedDescription)). Check the Xcode console for the raw response printed above."
            )
        }
    }

    // MARK: - Lunch

    private func retrieveLunch(baseURL: URL, token: String, orgId: Int) async throws -> LunchMenu {
        let lunchURL = baseURL.appendingPathComponent("api/lunchmenus/student/\(orgId)")

        var request = URLRequest(url: lunchURL)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue(appVersion, forHTTPHeaderField: "appversion")
        request.setValue(appOS, forHTTPHeaderField: "appos")

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SchoolSoftServiceError.networkError("Failed to fetch lunch menu from SchoolSoft (status \(status)).")
        }

        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("SchoolSoft /api/lunchmenus raw response:\n\(raw)")
        }
        #endif

        do {
            var weekCalendar = Calendar(identifier: .iso8601)
            weekCalendar.timeZone = .current
            guard let thisWeekStart = weekCalendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
                throw SchoolSoftServiceError.parsingError("Could not determine the current week.")
            }

            // Confirmed against a live response: a school with a
            // vegetarian option returns *two* of these objects for the
            // *same* week -- one per `dishCategoryName` ("Lunch" vs
            // "Vegetarisk") -- each with its own per-weekday dish text and
            // its own `dates` array giving the real calendar date for each
            // weekday. A school with just one menu sends a single object
            // (dishCategoryName absent). Decode defensively in case a
            // single-menu response isn't wrapped in an array at all.
            let weeks: [LunchWeekDTO]
            if let single = try? JSONDecoder().decode(LunchWeekDTO.self, from: data) {
                weeks = [single]
            } else {
                weeks = try JSONDecoder().decode([LunchWeekDTO].self, from: data)
            }

            // Merge same-date entries across DTOs into one LunchDay per
            // date, with both dish lists populated. `dates` (the real
            // calendar dates this DTO covers) is used when present, since
            // multiple DTOs for the same week means array position is NOT
            // a week offset -- a computed offset is only a fallback for a
            // DTO that omits `dates` entirely.
            var normalByDate: [Date: [String]] = [:]
            var vegetarianByDate: [Date: [String]] = [:]
            var order: [Date] = []

            for (index, week) in weeks.enumerated() {
                let fallbackWeekStart = weekCalendar.date(byAdding: .weekOfYear, value: index, to: thisWeekStart) ?? thisWeekStart
                for (date, dishes) in week.dayDishes(calendar: weekCalendar, fallbackWeekStart: fallbackWeekStart) {
                    let day = weekCalendar.startOfDay(for: date)
                    if !order.contains(day) { order.append(day) }
                    if week.isVegetarian {
                        vegetarianByDate[day, default: []].append(contentsOf: dishes)
                    } else {
                        normalByDate[day, default: []].append(contentsOf: dishes)
                    }
                }
            }

            let days = order.sorted().map { day in
                LunchDay(date: day, normalDishes: normalByDate[day] ?? [], vegetarianDishes: vegetarianByDate[day] ?? [])
            }

            return LunchMenu(days: days, lastUpdated: .now)
        } catch {
            throw SchoolSoftServiceError.parsingError(
                "Lunch menu format unexpected (\(error.localizedDescription)). Check the Xcode console for the raw response printed above."
            )
        }
    }

    // MARK: - Helpers

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw SchoolSoftServiceError.networkError(error.localizedDescription)
        }
    }

    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let pairs = fields.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

/// Mock service for testing without connecting to live SchoolSoft servers.
public final class MockSchoolSoftService: SchoolSoftScheduleService {
    public init() {}

    public func fetchSchedule(using credentials: SchoolSoftCredentials) async throws -> Schedule {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Schedule.sample
    }

    public func fetchLunchMenu(using credentials: SchoolSoftCredentials) async throws -> LunchMenu {
        try await Task.sleep(nanoseconds: 200_000_000)
        return LunchMenu.sample
    }
}

// MARK: - Login / token DTOs

private struct LoginResponse: Codable {
    var appKey: String
    var orgs: [Org]

    struct Org: Codable {
        var orgId: Int
    }
}

private struct TokenResponse: Codable {
    var token: String
    var expiryDate: String?
}

/// Data Transfer Object for one recurring timetable rule from
/// `/api/lessons/student/{orgId}`, confirmed against a live response.
///
/// Each entry is a recurring rule, not a single dated occurrence: it names
/// a weekday (`dayId`) and a time-of-day (`startTime`/`endTime`, both
/// stamped on the dummy date 1970-01-01), plus the set of actual ISO week
/// numbers it applies to (`weeksIntArray` / `periodWeeksIntArray` — SchoolSoft
/// already expands its internal bitmask into these arrays for you, no bit
/// math needed). `lesson(forWeek:weekStart:calendar:)` expands one rule into
/// a concrete `Lesson` only if it's active in the given week.
///
/// `dayId` is assumed to be 0 = Monday ... 4 = Friday based on the one
/// sample observed (dayId 0 for a Monday-looking entry) — this is NOT
/// officially confirmed. If lessons land on the wrong weekday in the
/// widget, this is the first thing to double-check (it may need to be
/// 1-based instead).
private struct LessonDTO: Codable {
    var id: Int?
    var subjectName: String?
    var roomName: String?
    var name: String?
    var dayId: Int?
    var startTime: String?
    var endTime: String?
    var length: Int?
    var excludeClass: Int?
    var weeksIntArray: [Int]?
    var periodWeeksIntArray: [Int]?
    var excludingWeeksIntArray: [Int]?

    func lesson(forWeek weekOfYear: Int, weekStart: Date, calendar: Calendar) -> Lesson? {
        guard (excludeClass ?? 0) == 0 else { return nil }

        let activeWeeks = Set(weeksIntArray ?? []).union(periodWeeksIntArray ?? [])
        guard !activeWeeks.isEmpty, activeWeeks.contains(weekOfYear) else { return nil }
        if let excluded = excludingWeeksIntArray, excluded.contains(weekOfYear) { return nil }

        guard let dayId, (0...4).contains(dayId) else { return nil }
        guard let day = calendar.date(byAdding: .day, value: dayId, to: weekStart) else { return nil }
        guard let startDate = Self.timeOfDay(startTime, on: day) else { return nil }

        let endDate = Self.timeOfDay(endTime, on: day)
            ?? length.map { startDate.addingTimeInterval(TimeInterval($0 * 60)) }
            ?? startDate.addingTimeInterval(3600)

        let teacherName = name?.trimmingCharacters(in: .whitespaces)
        let lessonId = "\(id.map(String.init) ?? UUID().uuidString)-w\(weekOfYear)"

        return Lesson(
            id: lessonId,
            subject: subjectName ?? "Class",
            room: roomName,
            teacher: (teacherName?.isEmpty ?? true) ? nil : teacherName,
            start: startDate,
            end: endDate
        )
    }

    /// Parses a "1970-01-01 HH:mm:ss.S" style time-of-day string and
    /// re-anchors it onto the real calendar `day`.
    private static func timeOfDay(_ raw: String?, on day: Date) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let trimmed = raw.split(separator: ".").first.map(String.init) ?? raw
        guard let parsed = formatter.date(from: trimmed) else { return nil }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = utcCalendar.dateComponents([.hour, .minute, .second], from: parsed)

        let localCalendar = Calendar.current
        return localCalendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: day
        )
    }
}

/// Data Transfer Object for one week's worth of lunch menus from
/// `/api/lunchmenus/student/{orgId}`, confirmed against a live response.
///
/// Each week is a single object with one string field per weekday (English
/// keys, Swedish dish text), e.g. `"monday": "Nötfärsbiff med kokt
/// potatis...\r\n"`. A day's value can contain multiple dishes separated
/// by "\r\n" (rare -- normally just one). Two other fields matter for
/// telling menus apart: `dishCategoryName` ("Lunch" / "Vegetarisk" in the
/// one live response seen so far -- a school with only one menu omits it),
/// and `dates`, the real ISO calendar dates (Mon...Sun) this particular
/// object's weekday fields apply to.
private struct LunchWeekDTO: Codable {
    var monday: String?
    var tuesday: String?
    var wednesday: String?
    var thursday: String?
    var friday: String?
    var dates: [String]?
    var dishCategoryName: String?

    var isVegetarian: Bool {
        dishCategoryName?.localizedCaseInsensitiveContains("veg") ?? false
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// One (date, dishes) pair per weekday this object has text for.
    /// Prefers this DTO's own `dates` (index 0 = Monday) over a computed
    /// offset from `fallbackWeekStart`, since a school can send multiple
    /// DTOs for the *same* week (one per `dishCategoryName`) rather than
    /// one per distinct future week -- `fallbackWeekStart` only applies
    /// when `dates` is missing entirely.
    func dayDishes(calendar: Calendar, fallbackWeekStart: Date) -> [(date: Date, dishes: [String])] {
        let weekdayTexts: [(offset: Int, text: String?)] = [
            (0, monday), (1, tuesday), (2, wednesday), (3, thursday), (4, friday)
        ]

        return weekdayTexts.compactMap { offset, text in
            guard let text else { return nil }
            let dishes = text
                .components(separatedBy: "\r\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !dishes.isEmpty else { return nil }

            let date: Date?
            if let isoDates = dates, offset < isoDates.count, let parsed = Self.isoDateFormatter.date(from: isoDates[offset]) {
                date = parsed
            } else {
                date = calendar.date(byAdding: .day, value: offset, to: fallbackWeekStart)
            }
            guard let date else { return nil }
            return (date, dishes)
        }
    }
}
