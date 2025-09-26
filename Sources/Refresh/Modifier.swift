//
//  Modifier.swift
//  Refresh
//
//  Created by Gesen on 2020/3/8.
//  https://github.com/wxxsw/Refresh

import SwiftUI
import SwiftUIIntrospect

@available(iOS 13.0, macOS 10.15, *)
extension Refresh {
    
    struct Modifier {
        @State private var isDragging: Bool = false
        
        @State private var observer: Coordinator?
        
        @State private var id: Int = 0
        @State private var headerUpdate: HeaderUpdateKey.Value
        @State private var headerPadding: CGFloat = 0
        
        @State private var footerUpdate: FooterUpdateKey.Value
        @State private var footerPreviousRefreshAt: Date?
        
        init(isEnableHeader: Bool, isEnableFooter: Bool) {
            _headerUpdate = State(initialValue: .init(enable: isEnableHeader))
            _footerUpdate = State(initialValue: .init(enable: isEnableFooter))
        }
        
        @Environment(\.defaultMinListRowHeight) var rowHeight
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension Refresh.Modifier: ViewModifier {
    
    func body(content: Content) -> some View {
        return GeometryReader { proxy in
            content
                .environment(\.refreshHeaderUpdate, self.headerUpdate)
                .environment(\.refreshFooterUpdate, self.footerUpdate)
                .padding(.top, self.headerPadding)
                .clipped(proxy.safeAreaInsets == .zero)
                .backgroundPreferenceValue(Refresh.HeaderAnchorKey.self) { v -> Color in
                    DispatchQueue.main.async { self.update(proxy: proxy, value: v) }
                    return Color.clear
                }
                .backgroundPreferenceValue(Refresh.FooterAnchorKey.self) { v -> Color in
                    DispatchQueue.main.async { self.update(proxy: proxy, value: v) }
                    return Color.clear
                }
                .id(self.id)
            
                .introspect(.scrollView, on: .iOS(.v13, .v14, .v15, .v16, .v17, .v18, .v26), customize: { scrollView in
                    scrollView.delegate = observer
                })
                .onAppear() {
                    observer = Coordinator(isDragging: $isDragging)
                }
        }
    }
    
    func update(proxy: GeometryProxy, value: Refresh.HeaderAnchorKey.Value) {
        guard let item = value.first else { return }
        guard footerUpdate.state != .refreshing else { return }
        
        let bounds = proxy[item.bounds]
        var update = headerUpdate
        
        update.progress = max(0, (bounds.maxY) / bounds.height)
        
        let state: RefreshState = update.progress > 1.01 ? .readyRefresh : .idle
        
        if (update.state == .refreshing && !item.refreshing) ||
            (update.state != .refreshing && item.refreshing) {
            update.state = item.refreshing ? .refreshing : state
            
            if !item.refreshing {
                id += 1
                DispatchQueue.main.async {
                    self.headerUpdate.progress = 0
                }
            }
        } else {
            update.state = (update.state == .refreshing || (!isDragging && state == .readyRefresh)) ? .refreshing : state
        }
        
        headerUpdate = update
        headerPadding = headerUpdate.state == .refreshing ? 0 : -max(rowHeight, bounds.height)
    }
    
    func update(proxy: GeometryProxy, value: Refresh.FooterAnchorKey.Value) {
        guard let item = value.first else { return }
        guard headerUpdate.progress == 0 else { return }
        
        let bounds = proxy[item.bounds]
        var update = footerUpdate
        
        if item.noMoreData {
            update.state = .noMoreData
        }
        else {
            if bounds.minY <= rowHeight || bounds.minY <= bounds.height {
                update.state = .idle
            } else if update.state == .refreshing && !item.refreshing {
                update.state = .idle
            } else {
                let preloadOffset = item.preloadOffset > 0 ? item.preloadOffset : -bounds.height
                let state: RefreshState = (proxy.size.height - bounds.minY + preloadOffset > 0) ? .readyRefresh : .idle
                update.state = (!isDragging && state == .readyRefresh) ? .refreshing : state
            }
            
            if update.state == .refreshing, footerUpdate.state != .refreshing {
                if let date = footerPreviousRefreshAt, Date().timeIntervalSince(date) < 0.1 {
                    update.state = .idle
                }
                footerPreviousRefreshAt = Date()
            }
        }
        
        footerUpdate = update
    }
}

class Coordinator: NSObject, UIScrollViewDelegate {
    @Binding var isDragging: Bool
    
    init(isDragging: Binding<Bool>) {
        _isDragging = isDragging
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isDragging = true
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isDragging = false
    }
}
