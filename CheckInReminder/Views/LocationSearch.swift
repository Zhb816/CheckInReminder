//
//  LocationSearch.swift
//  地址搜索：输入「XX大厦 / XX路」自动补全，选中后直接定位到该点
//

import Foundation
import MapKit
import CoreLocation

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
}

final class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var results: [SearchResult] = []

    /// 搜索关键词，变化即自动补全
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // 默认以中国为主要搜索范围，可按需改
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
        )
    }

    /// 把搜索范围锁定到当前位置附近，结果更准
    func focusOnCurrentLocation(_ coordinate: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(center: coordinate,
                                              span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    }

    func clear() {
        query = ""
        results = []
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.prefix(6).map { item in
            SearchResult(title: item.title,
                         subtitle: item.subtitle.isEmpty ? "" : item.subtitle,
                         completion: item)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    // MARK: - 补全项 → 真实坐标

    /// 把选中的补全项解析成坐标
    func resolve(_ result: SearchResult,
                 completion: @escaping (CLLocationCoordinate2D?, String?) -> Void) {
        let request = MKLocalSearch.Request(completion: result.completion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                print("[搜索] 解析失败: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            guard let item = response?.mapItems.first else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let coordinate = item.placemark.coordinate
            let name = [item.name, item.placemark.title].compactMap { $0 }.first
            DispatchQueue.main.async { completion(coordinate, name) }
        }
    }

    /// 直接搜索一段文字（不用补全列表，回车搜索时用）
    func search(text: String,
                completion: @escaping (CLLocationCoordinate2D?, String?) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = completer.region
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let item = response?.mapItems.first else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let name = [item.name, item.placemark.title].compactMap { $0 }.first
            DispatchQueue.main.async { completion(item.placemark.coordinate, name) }
        }
    }
}
