//
//  Clickstream.swift
//  Clickstream
//
//  Created by Anirudh Vyas on 21/04/20.
//  Copyright © 2020 Gojek. All rights reserved.
//
import Foundation
import SwiftProtobuf

/// Conform to this delegate to send the current user location details and set NTP Time.
public protocol ClickstreamDataSource: AnyObject {
    
    #if TRACKER_ENABLED
    /// Returns the current user location as `CSLocation` instance.
    /// - Returns: `CSLocation` instance.
    func currentUserLocation() -> CSLocation?
    #endif
    
    /// Returns NTP timestamp
    /// - Returns: NTP Date() instance
    func currentNTPTimestamp() -> Date?
}

public protocol ClickstreamDelegate: AnyObject {
    
    /// Provides Clickstream connection state changes
    /// - Parameter state: Clickstream.ConnectionState
    func onConnectionStateChanged(state: Clickstream.ConnectionState)
}

/// Primary class for integrating Clickstream.
public final class Clickstream {
    
    /// States the various states of Clicstream connection
    public enum ConnectionState {
        // When the socket is trying to connect
        case connecting
        // When the socket is about to be closed. can be called when the app moves to backgroud
        case closing
        // When the socket connection is closed
        case closed
        // When the socket connection is fails
        case failed
        // When the socket connection gets connected
        case connected
    }
    
    public enum ClickstreamError: Error, LocalizedError {
        /// Clickstream could not be initialised.
        case initialisation(String)
        
        public var errorDescription: String? {
            switch self {
            case .initialisation(let message):
                return NSLocalizedString("Clickstream initialisation error: \(message)", comment: "initialisation error")
            }
        }
    }
    
    /// Holds the configurations for the sdk.
    internal static var configurations: ClickstreamConstraints!
    
    /// Holds the event classification for the sdk.
    internal static var eventClassifier: ClickstreamEventClassification!
    
    #if TRACKER_ENABLED
    // Holds the health tracking configs for the SDK
    internal static var healthTrackingConfigs: ClickstreamHealthConfigurations?
    #endif
    
    /// Holds latest NTP date
    internal static var currentNTPTimestamp: Date? {
        get {
            let timestamp = sharedInstance?._dataSource?.currentNTPTimestamp()
            return timestamp
        }
    }
    
    /// Clickstream shared instance.
    private static var sharedInstance: Clickstream?
    
    private var dependencies: DefaultClickstreamDependencies?
    #if EVENT_VISUALIZER_ENABLED
    /// internal stored static variable which is a delegate
    /// to sent the events to client for visualization.
    /// If delegate is nil then no events are passed to client.
    internal weak static var _stateViewer: EventStateViewable?
    
    /// computed public property which sets
    /// and fetches the global `_stateViewer` variable
    public var stateViewer: EventStateViewable? {
        get {
            return Clickstream._stateViewer
        }
        set {
            Clickstream._stateViewer = newValue
        }
    }
    #endif
    #if ETE_TEST_SUITE_ENABLED
    internal static var ackEvent: AckEventDetails?
    #endif
    
    /// Public property to get Clickstream connection state
    public var clickstreamConnectionState: Clickstream.ConnectionState? {
        return Clickstream.connectionState
    }
    
    /// ClickstreamDataSource.
    private weak var _dataSource: ClickstreamDataSource?
    
    /// readonly public accessor for dataSource.
    public weak var dataSource: ClickstreamDataSource? {
        get {
            return _dataSource
        }
    }
    
    #if TRACKER_ENABLED
    /// CSCommonProperties
    private var _commonEventProperties: CSCommonProperties?
    
    /// readonly public accessor for CSCommonProperties.
    public var commonEventProperties: CSCommonProperties? {
        get {
            return _commonEventProperties
        } set {
            _commonEventProperties = newValue
            // Set Health Tracking based on userID/version
            self.setHealthTracker()
        }
    }
    #endif
    
    /// ClickstreamDelegate.
    private weak var delegate: ClickstreamDelegate?
    
    #if TRACKER_ENABLED
    private func setHealthTracker() {
        if let commonEventProperties = commonEventProperties,
           let healthTrackingConfigs = Clickstream.healthTrackingConfigs {
            Tracker.debugMode = healthTrackingConfigs.debugMode(userID: commonEventProperties.customer.identity,
                                                                    currentAppVersion: commonEventProperties.app.version)
        }
        
        Tracker.initialise() // Initialise Tracker
        
        if Tracker.debugMode {
            Tracker.sharedInstance?.commonProperties = commonEventProperties
        }
    }
    
    /// readonly internal accessor for location DTO.
    private var location: CSLocation? {
        get {
            let locationInfo = _dataSource?.currentUserLocation()
            if Tracker.debugMode {
                Tracker.sharedInstance?.location = locationInfo
            }
            return locationInfo
        }
    }
    #endif
    
    // MARK: - Building blocks of the SDK.
    private let networkBuilder: NetworkBuildable
    private let eventProcessor: EventProcessor
    private let eventWarehouser: EventWarehouser
    
    /// Private initialiser for the Clickstream Interface.
    /// - Parameters:
    ///   - networkBuilder: network builder instance
    ///   - eventWarehouser: event warehouser instance
    ///   - eventProcessor: event processor instance
    ///   - dataSource: dataSource for Clickstream
    private init(networkBuilder: NetworkBuildable,
                 eventWarehouser: EventWarehouser,
                 eventProcessor: EventProcessor,
                 dataSource: ClickstreamDataSource,
                 delegate: ClickstreamDelegate? = nil) {
        self.networkBuilder = networkBuilder
        self.eventWarehouser = eventWarehouser
        self.eventProcessor = eventProcessor
        self._dataSource = dataSource
        self.delegate = delegate
    }
    
    static var updateConnectionStatus: Bool = false
    
    /// Use this property to pass application namew without any space or special characters.
    static var appPrefix: String = ""
    
    /// Returns the shared Clickstream instance.
    /// - Returns: `Clickstream` instance.
    public static func getInstance() -> Clickstream? {
        return sharedInstance
    }
    
    public static func setLogLevel(_ level: Logger.LogLevel) {
        Logger.logLevel = level
    }
    
    /// Provides whether clickstream is connected to the network or not
    public var isClickstreamConnectedToNetwork: Bool {
        get {
            return dependencies?.isSocketConnected ?? false
        }
    }
    
    /// Stops the Clickstream tracking.
    public static func stopTracking() {
        sharedInstance?.eventWarehouser.stop()
    }
    
    /// Destroys the Clickstream instance.
    /// Calls the 'stopTracking' method internally.
    public static func destroy() {
        stopTracking()
        sharedInstance = nil
    }
    
    /// Call this method add an event to tracking.
    /// - Parameter event: readonly public accessor for CSEventDTO
    /// CSEventDTO consists of
    ///     guid:- event guid
    ///     message:- product proto message for an event which needs to be tracked.
    ///     timestamp:- timestamp of the event
    public func trackEvent(with event: ClickstreamEvent) {
        self.eventProcessor.createEvent(event: event)
    }
    
    /// Initializes an instance of the API with the given configurations.
    /// Returns a new Clickstream instance API object. This allows you to create one instance only.
    /// - Parameters:
    ///   - networkConfiguration: Network Configurations needed for connecting socket
    ///   - constraints: Clickstream constraints passed from the integrating app.
    ///   - dataSource: ClickstreamDataSource instance passed from the integrating app.
    ///   - eventClassification: Clickstream event classification passed from the integrating app.
    ///   - request: URL request with secret code for the services to authenticate.
    ///   - appPrefix: Application name without any space or special characters that needs
    ///   to be passed from integrating app.
    /// - Returns: returns a Clickstream instance to keep throughout the project.
    ///            You can always get the instance by calling getInstance()
    #if TRACKER_ENABLED
    @discardableResult public static func initialise(with request: URLRequest,
                                                     configurations: ClickstreamConstraints,
                                                     eventClassification: ClickstreamEventClassification,
                                                     healthTrackingConfigs: ClickstreamHealthConfigurations,
                                                     dataSource: ClickstreamDataSource,
                                                     delegate: ClickstreamDelegate? = nil,
                                                     updateConnectionStatus: Bool = false,
                                                     appPrefix: String) throws -> Clickstream? {
        do {
            return try initializeClickstream(
                with: request,
                configurations: configurations,
                eventClassification: eventClassification,
                dataSource: dataSource,
                delegate: delegate,
                updateConnectionStatus: updateConnectionStatus,
                appPrefix: appPrefix)
        } catch {
            print("Cannot initialise Clickstream. Dependencies could not be initialised.",.critical)
            // Relay the database error.
            throw Clickstream.ClickstreamError.initialisation(error.localizedDescription)
        }
    }
    #else
    @discardableResult public static func initialise(with request: URLRequest,
                                                     configurations: ClickstreamConstraints,
                                                     eventClassification: ClickstreamEventClassification,
                                                     dataSource: ClickstreamDataSource,
                                                     delegate: ClickstreamDelegate? = nil,
                                                     updateConnectionStatus: Bool = false,
                                                     appPrefix: String) throws -> Clickstream? {
        do {
            return try initializeClickstream(
                with: request,
                configurations: configurations,
                eventClassification: eventClassification,
                dataSource: dataSource,
                delegate: delegate,
                updateConnectionStatus: updateConnectionStatus,
                appPrefix: appPrefix)
        } catch {
            print("Cannot initialise Clickstream. Dependencies could not be initialised.",.critical)
            // Relay the database error.
            throw Clickstream.ClickstreamError.initialisation(error.localizedDescription)
        }
    }
    #endif
    
    static func initializeClickstream(with request: URLRequest,
                                      configurations: ClickstreamConstraints,
                                      eventClassification: ClickstreamEventClassification,
                                      dataSource: ClickstreamDataSource,
                                      delegate: ClickstreamDelegate? = nil,
                                      updateConnectionStatus: Bool = false,
                                      appPrefix: String) throws -> Clickstream? {
        let semaphore = DispatchSemaphore(value: 1)
        defer {
            semaphore.signal()
        }
        semaphore.wait()
        
        guard sharedInstance != nil else {
            
            // Assign the configurations.
            Clickstream.configurations = configurations
            Clickstream.eventClassifier = eventClassification
            Clickstream.updateConnectionStatus = updateConnectionStatus
            Clickstream.appPrefix = appPrefix.lowercased().replacingOccurrences(of: " ", with: "")
            
            // All the dependency injections pertaining to the clickstream blocks happen here!
            // Load default dependencies.
            do {
                let dependencies = try DefaultClickstreamDependencies(with: request)
                sharedInstance = Clickstream(networkBuilder: dependencies.networkBuilder,
                                             eventWarehouser: dependencies.eventWarehouser,
                                             eventProcessor: dependencies.eventProcessor,
                                             dataSource: dataSource,
                                             delegate: delegate)
                sharedInstance?.dependencies = dependencies // saving a copy of dependencies
            } catch {
                print("Cannot initialise Clickstream. Dependencies could not be initialised.",.critical)
                // Relay the database error.
                throw Clickstream.ClickstreamError.initialisation(error.localizedDescription)
            }
            
            return sharedInstance
        }
        return sharedInstance
    }
    
    @AtomicConnectionState internal static var connectionState: Clickstream.ConnectionState {
        didSet {
            sharedInstance?.delegate?.onConnectionStateChanged(state: connectionState)
        }
    }
}

// MARK: - Code below here is support for the Clickstream's EventVisualizer.
#if EVENT_VISUALIZER_ENABLED
extension Clickstream {
    
    /// Initialise event visualizer state tracking
    /// - Parameters:
    ///   - guid:String
    ///   - eventTimestamp:String
    ///   - storageGuid:String
    ///   - storageEventTimestamp:String
    public func setEventVisualizerStateTracking(guid: String,
                                                eventTimestamp: String) {
        Constants.EventVisualizer.guid = guid
        Constants.EventVisualizer.eventTimestamp = eventTimestamp
    }
}
#endif

@propertyWrapper
struct AtomicConnectionState {
    private let dispatchQueue = DispatchQueue(label: Constants.QueueIdentifiers.atomicAccess.rawValue, attributes: .concurrent)
    private var state: Clickstream.ConnectionState = .closed
    var wrappedValue: Clickstream.ConnectionState {
        get { dispatchQueue.sync { state } }
        set { dispatchQueue.sync(flags: .barrier) { state = newValue } }
    }
}
