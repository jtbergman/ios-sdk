import Foundation

import Nimble
import Quick
import OHHTTPStubs
#if !COCOAPODS
import OHHTTPStubsSwift
#endif
@testable import Statsig

fileprivate struct Data {
    static let GateKey = "gate"
    static let HashGateKey = GateKey.sha256()
    static let FeatureGates = [
        HashGateKey: ["value": true, "rule_id": "rule_id_2"]
    ]

    static let ConfigKey = "config"
    static let HashConfigKey = ConfigKey.sha256()

    static let AnotherConfigKey = "another_config"
    static let HashAnotherConfigKey = AnotherConfigKey.sha256()

    static let DeviceBasedConfigKey = "device_based_config"
    static let HashDeviceBasedConfigKey = DeviceBasedConfigKey.sha256()

    static let DynamicConfigs = [
        HashConfigKey: [
            "name": HashConfigKey,
            "rule_id": "default",
            "value": ["key": "value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
        ],
        HashAnotherConfigKey: [
            "name": HashAnotherConfigKey,
            "rule_id": "default",
            "value": ["key": "another_value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
        ],
        HashDeviceBasedConfigKey: [
            "name": HashDeviceBasedConfigKey,
            "rule_id": "default",
            "value": ["key": "device_based_value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
            "is_device_based": true
        ],
    ]

    static let LayerConfigWithExperimentKey = "layer_with_exp"
    static let HashLayerConfigWithExperimentKey = LayerConfigWithExperimentKey.sha256()

    static let LayerConfigWithoutExperimentKey = "layer_without_exp"
    static let HashLayerConfigWithoutExperimentKey = LayerConfigWithoutExperimentKey.sha256()

    static let LayerConfigs: [String: Any] = [
        HashLayerConfigWithExperimentKey: [
            "name": HashLayerConfigWithExperimentKey,
            "rule_id": "default",
            "value": ["key": "value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
            "allocated_experiment_name": HashConfigKey
        ],
        HashLayerConfigWithoutExperimentKey: [
            "name": HashLayerConfigWithExperimentKey,
            "rule_id": "default",
            "value": ["key": "another_value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
        ]
    ]

    static let CacheValues = [
        "dynamic_configs": DynamicConfigs,
        "feature_gates": FeatureGates,
        "layer_configs": LayerConfigs
    ]

    static let StickyValues = [
        HashConfigKey: [
            "rule_id": "sticky",
            "value": ["key": "value_sticky"],
        ],
    ]
}

class LayerConfigSpec: QuickSpec {

    override func spec() {
        describe("using getLayerConfig") {
            let client = StatsigClient(sdkKey: "", user: nil, options: nil, completion: nil)
            var store: InternalStore!

            beforeEach {
                InternalStore.deleteAllLocalStorage()
                store = InternalStore(StatsigUser(userID: "dloomb"))

                store.cache.saveValuesForCurrentUser(Data.CacheValues)
            }

            it("returns the experiment values") {
                let config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                let another = store.getLayer(client: client, forName: Data.LayerConfigWithoutExperimentKey)
                expect(another?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("another_value"))
            }

            it("should return a sticky value") {
                var config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey, keepDeviceValue: true)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                var updatedValues: [String: Any] = Data.CacheValues
                updatedValues[jsonDict: "dynamic_configs"]?[jsonDict: Data.HashConfigKey]?["is_user_in_experiment"] = false

                store = InternalStore(StatsigUser(userID: "dloomb")) // reload the cache, and user is no longer in the experiment, but value should stick because experiment is active

                waitUntil { done in
                    store.set(values: updatedValues) {
                        done()
                    }
                }

                config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey, keepDeviceValue: true)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                updatedValues[jsonDict: "layer_configs"]?[jsonDict: Data.HashLayerConfigWithExperimentKey] = [
                    "name": Data.HashLayerConfigWithExperimentKey,
                    "rule_id": "default",
                    "value": ["key": "another_value"],
                    "is_user_in_experiment": true,
                    "is_experiment_active": true,
                    "allocated_experiment_name": "completely_different_exp"
                ]

                // reload the cache, and user is allocated to a different experiment,
                // but should still get same value because previous experiment is still active
                store = InternalStore(StatsigUser(userID: "dloomb"))

                waitUntil { done in
                    store.set(values: updatedValues) {
                        done()
                    }
                }

                config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey, keepDeviceValue: true)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                updatedValues[jsonDict: "dynamic_configs"]?[jsonDict: Data.HashConfigKey]?["is_experiment_active"] = false
                // reload the cache, and previous experiment is no longer active, so should get new value
                store = InternalStore(StatsigUser(userID: "dloomb"))

                waitUntil { done in
                    store.set(values: updatedValues) {
                        done()
                    }
                }

                config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey, keepDeviceValue: true)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("another_value"))
            }

            it("should wipe sticky value when keepDeviceValue is false") {
                var config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey, keepDeviceValue: true)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                var updatedValues: [String: Any] = Data.CacheValues
                updatedValues[jsonDict: "layer_configs"]?[jsonDict: Data.HashLayerConfigWithExperimentKey] = [
                    "name": Data.HashLayerConfigWithExperimentKey,
                    "rule_id": "default",
                    "value": ["key": "another_value"],
                    "is_user_in_experiment": true,
                    "is_experiment_active": true,
                    "allocated_experiment_name": Data.AnotherConfigKey
                ]

                store = InternalStore(StatsigUser(userID: "dloomb"))
                waitUntil { done in
                    store.set(values: updatedValues) {
                        done()
                    }
                }
                config = store.getLayer(client: client, forName: Data.LayerConfigWithExperimentKey, keepDeviceValue: false)
                expect(config?.getValue(forKey: "key", defaultValue: "ERR")).to(equal("another_value"))
            }
        }
    }
}