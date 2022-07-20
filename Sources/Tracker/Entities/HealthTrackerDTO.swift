//
//  HealthTrackerDTO.swift
//  Clickstream
//
//  Created by Abhijeet Mallick on 30/05/22.
//  Copyright © 2022 Gojek. All rights reserved.
//

import Foundation

/// Stream of Health events generated by Clickstream which a client can listen and send it to any third party analytics tracker
/// This can be used to measure the Clickstream SDK event drop rate, socket failure or any other backend issues.
public struct HealthTrackerDTO {
    
    /// Health event name
    public internal(set) var eventName: String!
    
    /// Error reason like socket failure or JSON parsion error
    public internal(set) var failureReason: String?
    
    /// Time taken to connect to socket
    public internal(set) var timeToConnection: String?
    
    /// List of GUIDs of client app event
    public internal(set) var eventGUIDs: [String]?
    
    /// Batch GUID of client app event
    public internal(set) var eventBatchGUIDs: [String]?
    
    /// Client app session ID
    public internal(set) var sessionID: String?
    
    /// Number of health events being sent
    public internal(set) var eventCount: Int?
}