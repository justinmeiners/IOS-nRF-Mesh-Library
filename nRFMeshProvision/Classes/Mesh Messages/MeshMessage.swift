/*
* Copyright (c) 2019, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import Foundation

public enum MeshMessageSecurity {
    /// Message will be sent with 32-bit Transport MIC.
    case low
    /// Message will be sent with 64-bit Transport MIC.
    /// Unsegmented messages cannot be sent with this option.
    case high
}

/// The base class of every mesh message. Mesh messages can be sent and
/// and received from the mesh network.
public protocol BaseMeshMessage {
    /// Message parameters as Data.
    var parameters: Data? { get }
    
    /// This initializer should construct the message based on the received
    /// parameters.
    ///
    /// - parameter parameters: The Access Layer parameters.
    init?(parameters: Data)
}

/// The base class of every mesh message. Mesh messages can be sent and
/// and received from the mesh network. For messages with the opcode known
/// during compilation a `StaticMeshMessage` protocol should be preferred.
///
/// Parameters `security` and `isSegmented` are checked and should be set
/// only for outgoing messages.
public protocol MeshMessage: BaseMeshMessage {
    /// The message Op Code.
    var opCode: UInt32 { get }
    /// Returns whether the message should be sent or has been sent using
    /// 32-bit or 64-bit TransMIC value. By default `.low` is returned.
    ///
    /// Only Segmented Access Messages can use 64-bit MIC. If the payload
    /// is shorter than 11 bytes, make sure you return `true` from
    /// `isSegmented`, otherwise this field will be ignored.
    var security: MeshMessageSecurity { get }
    /// Returns whether the message should be sent or was sent as
    /// Segmented Access Message. By default, this parameter returns
    /// `false`.
    ///
    /// To force segmentation for shorter messages return `true` despite
    /// payload length. If payload size is longer than 11 bytes this
    /// field is not checked as the message must be segmented.
    var isSegmented: Bool { get }
}

/// The base class for acknowledged messages.
///
/// An acknowledged message is transmitted and acknowledged by each
/// receiving element by responding to that message. The response is
/// typically a status message. If a response is not received within
/// an arbitrary time period, the message will be retransmitted
/// automatically until the timeout occurs.
public protocol AcknowledgedMeshMessage: MeshMessage {
    /// The Op Code of the response message.
    var responseOpCode: UInt32 { get }
}

/// A type of a mesh message which opcode is known during compilation time.
public protocol StaticMeshMessage: MeshMessage {
    /// The message Op Code.
    static var opCode: UInt32 { get }
}

public protocol StaticAcknowledgedMeshMessage: AcknowledgedMeshMessage, StaticMeshMessage {
    /// The Type of the response message.
    static var responseType: StaticMeshMessage.Type { get }
}

/// A mesh message containing the operation status.
public protocol StatusMessage: MeshMessage {
    /// Returns whether the operation was successful or not.
    var isSuccess: Bool { get }
    
    /// The status as String.
    var message: String { get }
}

/// A message with Transaction Identifier.
///
/// The Transaction Identifier will automatically be set and incremented
/// each time a message is sent. The counter is reused for all types that
/// extend this protocol.
public protocol TransactionMessage: MeshMessage {
    /// Transaction identifier. If not set, this field will automatically
    /// be set when the message is being sent or received.
    var tid: UInt8! { get set }
    /// Whether the message should start a new transaction.
    ///
    /// The messages within a transaction carry the cumulative values of
    /// a field. In case one or more messages within a transaction are not
    /// received by the Server (e.g., as a result of radio collisions),
    /// the next received message will make up for the lost messages,
    /// carrying cumulative values of the field.
    ///
    /// A new transaction is started when this field is set to `true`,
    /// or when the last message of the transaction was sent 6 or
    /// more seconds earlier.
    ///
    /// This defaults to `false`, which means that each new message will
    /// receive a new transaction identifier (if not set explicitly).
    var continueTransaction: Bool { get }
}

public protocol TransitionMessage: MeshMessage {
    /// The Transition Time field identifies the time that an element will
    /// take to transition to the target state from the present state.
    var transitionTime: TransitionTime? { get }
    /// Message execution delay in 5 millisecond steps.
    var delay: UInt8? { get }
}

public protocol TransitionStatusMessage: MeshMessage {
    /// The Remaining Time field identifies the time that an element will
    /// take to transition to the target state from the present state.
    var remainingTime: TransitionTime? { get }
}

// MARK: - Default values

public extension MeshMessage {
    
    var security: MeshMessageSecurity {
        return .low
    }
    
    var isSegmented: Bool {
        return false
    }
    
}

public extension TransactionMessage {
    
    var continueTransaction: Bool {
        return false
    }
    
    /// Returns whether this message is a continuation of another
    /// transaction message sent before at the given timestamp.
    ///
    /// - parameter previousTid: The TID of the previously received message.
    /// - parameter timestamp:   The timestamp when the previous message was
    ///                          received.
    func isNewTransaction(previousTid: UInt8, timestamp: Date) -> Bool {
        return tid != previousTid || timestamp.timeIntervalSinceNow < -6.0
    }
    
}

public extension StaticMeshMessage {
    
    var opCode: UInt32 {
        return Self.opCode
    }
    
}

public extension StaticAcknowledgedMeshMessage {
    
    var responseOpCode: UInt32 {
        return Self.responseType.opCode
    }
    
}

// MARK: - Private API

internal extension MeshMessage {
    
    /// Whether the message is a Vendor Message, or not.
    ///
    /// Vendor messages use 3-byte Op Codes, where the 2 most significant
    /// bits of the first octet are set to 1. The remaining bits of the
    /// first octet are the operation code, while the last 2 bytes are the
    /// Company Identifier (Big Endian), as registered by Bluetooth SIG.
    var isVendorMessage: Bool {
        return opCode & 0xFFC00000 == 0x00C00000
    }
    
    /// Whether the message is an acknowledged message, or not.
    var isAcknowledged: Bool {
        return self is AcknowledgedMeshMessage
    }
    
}

// MARK: - Other

extension MeshMessageSecurity {
    
    /// Returns the Transport MIC size in bytes: 4 for 32-bit
    /// or 8 for 64-bit size.
    var transportMicSize: UInt8 {
        switch self {
        case .low:  return 4
        case .high: return 8
        }
    }
    
}

extension MeshMessageSecurity: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .high:
            return "High (64-bit TransMIC)"
        case .low:
            return "Low (32-bit TransMIC)"
        }
    }
    
}
