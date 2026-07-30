import Foundation
#if canImport(CallKit)
import CallKit
#endif
#if canImport(CoreTelephony)
import CoreTelephony
#endif

protocol AgentIOSTelephonyStatusProviding {
  func telephonyStatus(nowMillis: Int64) -> AgentMcpJSONObject
  func callState(nowMillis: Int64) -> AgentMcpJSONObject
}

struct AgentIOSDefaultTelephonyStatusProvider: AgentIOSTelephonyStatusProviding {
  func telephonyStatus(nowMillis: Int64) -> AgentMcpJSONObject {
    let callState = currentCallState()
    #if canImport(CoreTelephony)
    let networkInfo = CTTelephonyNetworkInfo()
    let carriers = carrierRows(networkInfo)
    let firstCarrier = carriers.first?.objectValue ?? [:]
    let technologies = radioAccessTechnologyRows(networkInfo)
    let carrierName = firstCarrier["carrier_name"] ?? .string("")
    let country = firstCarrier["iso_country_code"] ?? .string("")
    return [
      "phone_type": .string(carriers.isEmpty ? "not_exposed_ios" : "cellular_capable_ios"),
      "sim_state": .string(carriers.isEmpty ? "not_available_or_not_exposed_ios" : "carrier_info_available"),
      "network_operator_name": carrierName,
      "network_country_iso": country,
      "data_state": .string("not_exposed_ios"),
      "call_state": .string(callState.state),
      "data_enabled": .null,
      "carrier_count": .int(Int64(carriers.count)),
      "carriers": .array(carriers),
      "radio_access_technologies": .array(technologies),
      "call_state_scope": .string(callState.scope),
      "identifiers_included": .bool(false),
      "scope": .string("app_visible_ios_telephony_status"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #else
    return [
      "phone_type": .string("not_exposed_ios"),
      "sim_state": .string("not_exposed_ios"),
      "network_operator_name": .string(""),
      "network_country_iso": .string(""),
      "data_state": .string("not_exposed_ios"),
      "call_state": .string(callState.state),
      "data_enabled": .null,
      "carrier_count": .int(0),
      "carriers": .array([]),
      "radio_access_technologies": .array([]),
      "call_state_scope": .string(callState.scope),
      "identifiers_included": .bool(false),
      "scope": .string("app_visible_ios_telephony_status_unavailable"),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
    #endif
  }

  func callState(nowMillis: Int64) -> AgentMcpJSONObject {
    let state = currentCallState()
    return [
      "call_state": .string(state.state),
      "active_call_count": .int(Int64(state.activeCalls)),
      "outgoing_call_count": .int(Int64(state.outgoingCalls)),
      "on_hold_call_count": .int(Int64(state.onHoldCalls)),
      "ringing_detection_supported": .bool(false),
      "continuous_listener_supported": .bool(false),
      "identifiers_included": .bool(false),
      "scope": .string(state.scope),
      "observed_at_epoch_ms": .int(nowMillis)
    ]
  }

  private struct CallSummary {
    var state: String
    var activeCalls: Int
    var outgoingCalls: Int
    var onHoldCalls: Int
    var scope: String
  }

  private func currentCallState() -> CallSummary {
    #if canImport(CallKit)
    let calls = CXCallObserver().calls.filter { !$0.hasEnded }
    return CallSummary(
      state: calls.isEmpty ? "idle" : "off_hook",
      activeCalls: calls.count,
      outgoingCalls: calls.filter(\.isOutgoing).count,
      onHoldCalls: calls.filter(\.isOnHold).count,
      scope: "app_visible_ios_callkit"
    )
    #else
    return CallSummary(
      state: "unknown",
      activeCalls: 0,
      outgoingCalls: 0,
      onHoldCalls: 0,
      scope: "app_visible_ios_callkit_unavailable"
    )
    #endif
  }

  #if canImport(CoreTelephony)
  private func carrierRows(_ networkInfo: CTTelephonyNetworkInfo) -> [AgentMcpJSONValue] {
    let providers = networkInfo.serviceSubscriberCellularProviders ?? [:]
    let carriers: [(String, CTCarrier)]
    if providers.isEmpty, let fallback = networkInfo.subscriberCellularProvider {
      carriers = [("default", fallback)]
    } else {
      carriers = providers.sorted { $0.key < $1.key }
    }
    return carriers.prefix(8).map { serviceId, carrier in
      .object([
        "service_id": .string(bounded(serviceId, 80)),
        "carrier_name": .string(bounded(carrier.carrierName ?? "", 160)),
        "iso_country_code": .string(bounded(carrier.isoCountryCode ?? "", 8)),
        "mobile_country_code": .string(bounded(carrier.mobileCountryCode ?? "", 8)),
        "mobile_network_code": .string(bounded(carrier.mobileNetworkCode ?? "", 8)),
        "allows_voip": .bool(carrier.allowsVOIP),
        "identifiers_included": .bool(false)
      ])
    }
  }

  private func radioAccessTechnologyRows(_ networkInfo: CTTelephonyNetworkInfo) -> [AgentMcpJSONValue] {
    let technologies = networkInfo.serviceCurrentRadioAccessTechnology ?? [:]
    let rows: [(String, String)]
    if technologies.isEmpty, let fallback = networkInfo.currentRadioAccessTechnology {
      rows = [("default", fallback)]
    } else {
      rows = technologies.sorted { $0.key < $1.key }
    }
    return rows.prefix(8).map { serviceId, technology in
      .object([
        "service_id": .string(bounded(serviceId, 80)),
        "radio_access_technology": .string(bounded(technology, 160))
      ])
    }
  }
  #endif

  private func bounded(_ value: String, _ limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }
}
