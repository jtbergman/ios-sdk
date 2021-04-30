import Foundation

import Quick
import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import Statsig

class NetworkServiceSpec: QuickSpec {
    override func spec() {
        describe("using NetworkService to make network requests to Statsig API endpoints") {
            let sdkKey = "client-api-key"
            afterEach {
                HTTPStubs.removeAllStubs()
                InternalStore.deleteLocalStorage()
            }

            it("should send the correct request data when calling fetchInitialValues()") {
                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?
                stub(condition: isHost("api.statsig.com")) { request in
                    actualRequest = request
                    actualRequestHttpBody = try! JSONSerialization.jsonObject(
                        with: request.ohhttpStubs_httpBody!,
                        options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let ns = NetworkService(sdkKey: "client-api-key", options: StatsigOptions(), store: InternalStore())
                ns.fetchInitialValues(forUser: StatsigUser(userID: "jkw"), completion: nil)

                expect(actualRequestHttpBody?.keys).toEventually(contain("user", "statsigMetadata"))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString).toEventually(equal("https://api.statsig.com/v1/initialize"))
            }

            it("should send the correct request data when calling sendEvents(), and returns the request data back if request fails") {
                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?

                var actualRequestData: Data?
                var returnedRequestData: Data?

                stub(condition: isHost("api.statsig.com")) { request in
                    actualRequest = request
                    actualRequestHttpBody = try! JSONSerialization.jsonObject(
                        with: request.ohhttpStubs_httpBody!,
                        options: []) as! [String: Any]
                    actualRequestData = request.ohhttpStubs_httpBody
                    return HTTPStubsResponse(error: NSError(domain: NSURLErrorDomain, code: 403))
                }

                let ns = NetworkService(sdkKey: "client-api-key", options: StatsigOptions(), store: InternalStore())
                let user = StatsigUser(userID: "jkw")
                waitUntil { done in
                    ns.sendEvents(forUser: user, events: [Event(user: user, name: "test_event", value: 9.99, disableCurrentVCLogging: false)])
                    { errorMessage, jsonData in
                        returnedRequestData = jsonData
                        done()
                    }
                }

                expect(actualRequestHttpBody?.keys).toEventually(contain("user", "statsigMetadata", "events"))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString).toEventually(equal("https://api.statsig.com/v1/log_event"))
                expect(actualRequestData).toEventually(equal(returnedRequestData))
            }

            it("should send the correct request data when calling sendRequestsWithData(), and returns the request data back if request fails") {
                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?

                var actualRequestData: [Data] = []
                var returnedRequestData: [Data] = []

                stub(condition: isHost("api.statsig.com")) { request in
                    actualRequest = request
                    actualRequestHttpBody = try! JSONSerialization.jsonObject(
                        with: request.ohhttpStubs_httpBody!,
                        options: []) as! [String: Any]
                    actualRequestData.append(request.ohhttpStubs_httpBody!)
                    return HTTPStubsResponse(error: NSError(domain: NSURLErrorDomain, code: 403))
                }

                let ns = NetworkService(sdkKey: "client-api-key", options: StatsigOptions(), store: InternalStore())
                let user = StatsigUser(userID: "jkw")
                var data = [Data]()
                for index in 1...10 {
                    let params: [String: Any] = [
                        "user": StatsigUser(userID: String(index)).toDictionary(),
                        "events": [Event(user: user, name: "test_event_\(index)", value: index, disableCurrentVCLogging: false).toDictionary()]
                    ]
                    let d = try! JSONSerialization.data(withJSONObject: params)
                    data.append(d)
                }

                waitUntil { done in
                    ns.sendRequestsWithData(data) { failedData in
                        returnedRequestData = failedData!
                        done()
                    }
                }

                expect(actualRequestHttpBody?.keys).toEventually(contain("user", "events"))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString).toEventually(equal("https://api.statsig.com/v1/log_event"))
                expect(actualRequestData).toEventually(equal(returnedRequestData))
            }

            it("should be rate limited to a max of 10 concurrent requests") {
                var requestCount = 0;
                stub(condition: isHost("api.statsig.com")) { request in
                    requestCount += 1;
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil).responseTime(1000)
                }
                let ns = NetworkService(sdkKey: "client-api-key", options: StatsigOptions(), store: InternalStore())
                for index in 1...20 {
                    let user = StatsigUser(userID: String(index))
                    ns.sendEvents(forUser: user, events: [Event(user: user, name: "test_event", value: index,
                                                                disableCurrentVCLogging: false)]) {_, _ in}
                }
                expect(requestCount).toEventually(equal(10))
            }
        }
    }
}