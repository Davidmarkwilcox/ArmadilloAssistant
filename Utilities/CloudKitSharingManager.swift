//  CloudKitSharingManager.swift
//  ArmadilloAssistant
//
//  File: CloudKitSharingManager.swift
//  Description: Centralizes CloudKit workspace sharing for the app. This manager owns the
//  shared workspace root record, reuses a single CKShare when available, and provides the
//  share object needed by Settings > Team to present Apple's Cloud sharing controller.
//  Interacts with: Persistence.swift for NSPersistentCloudKitContainer configuration and
//  SettingsView.swift for Team UI.
//

import Foundation
import Combine
import CloudKit

@MainActor
final class CloudKitSharingManager: ObservableObject {

    static let shared = CloudKitSharingManager()
    private let isDebugLoggingEnabled: Bool = true

    static let containerIdentifier = "iCloud.com.DavidMWilcox.ArmadilloAssistant"
    let container: CKContainer
    let privateDatabase: CKDatabase
    let sharedDatabase: CKDatabase
    let systemSharingUIObserver: CKSystemSharingUIObserver

    @Published private(set) var shareStatusText: String = "Workspace sharing not configured"
    @Published private(set) var activeShareRecordID: CKRecord.ID?
    @Published private(set) var activeShareURL: URL?
    @Published private(set) var activeShare: CKShare?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastErrorMessage: String = ""
    @Published private(set) var currentUserIsOwner: Bool = true
    @Published private(set) var ownerDisplayName: String = "You"
    @Published private(set) var isInviteLinkReady: Bool = false
    @Published private(set) var inviteStatusText: String = "Prepare the workspace to enable invitations"
    @Published private(set) var activeWorkspaceRecordID: CKRecord.ID?
    @Published private(set) var canPresentShareSheet: Bool = false
    @Published private(set) var participantSummaries: [ParticipantSummary] = []

    private let workspaceRecordType = "Workspace"
    private let workspaceRecordName = "primary-workspace"
    private let workspaceZoneName = "TeamWorkspaceZone"
    private let localShareRecordNameDefaultsKey = "cloudkitsharingmanager.activeShareRecordName"
    private let localShareZoneNameDefaultsKey = "cloudkitsharingmanager.activeShareZoneName"
    private let localShareOwnerNameDefaultsKey = "cloudkitsharingmanager.activeShareOwnerName"

    private init() {
        self.container = CKContainer(identifier: Self.containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
        self.sharedDatabase = container.sharedCloudDatabase
        self.systemSharingUIObserver = CKSystemSharingUIObserver(container: container)

        let saveShareHandler: @Sendable (CKRecord.ID, Result<CKShare, Error>) -> Void = { [weak self] _, result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success(let share):
                    self.activeShareRecordID = share.recordID
                    self.activeShareURL = share.url
                    self.activeShare = share
                    self.syncParticipantSummaries(from: share)
                    self.persistActiveShareRecordID(share.recordID)
                    self.canPresentShareSheet = true
                    self.isInviteLinkReady = (share.url != nil)
                    self.inviteStatusText = share.url == nil
                        ? "Workspace share is ready. Use the Apple share sheet to invite participants."
                        : "Invitation link is ready"
                    self.shareStatusText = "Workspace share is ready"
                    self.lastErrorMessage = ""
                    self.log("System sharing UI saved share: \(share.recordID.recordName)")

                case .failure(let error):
                    self.lastErrorMessage = error.localizedDescription
                    self.log("System sharing UI failed to save share: \(error.localizedDescription)")
                }
            }
        }
        self.systemSharingUIObserver.systemSharingUIDidSaveShareBlock = saveShareHandler

        let stopSharingHandler: @Sendable (CKRecord.ID, Result<Void, Error>) -> Void = { [weak self] _, result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    self.activeShareRecordID = nil
                    self.activeShareURL = nil
                    self.activeShare = nil
                    self.participantSummaries = []
                    self.persistActiveShareRecordID(nil)
                    self.canPresentShareSheet = false
                    self.isInviteLinkReady = false
                    self.inviteStatusText = "Prepare the workspace to enable invitations"
                    self.shareStatusText = "Workspace sharing not configured"
                    self.log("System sharing UI stopped sharing")

                case .failure(let error):
                    self.lastErrorMessage = error.localizedDescription
                    self.log("System sharing UI failed to stop sharing: \(error.localizedDescription)")
                }
            }
        }
        self.systemSharingUIObserver.systemSharingUIDidStopSharingBlock = stopSharingHandler

        log("Initialized CloudKitSharingManager")
    }

    private func persistActiveShareRecordID(_ recordID: CKRecord.ID?) {
        if let recordID {
            UserDefaults.standard.set(recordID.recordName, forKey: localShareRecordNameDefaultsKey)
            UserDefaults.standard.set(recordID.zoneID.zoneName, forKey: localShareZoneNameDefaultsKey)
            UserDefaults.standard.set(recordID.zoneID.ownerName, forKey: localShareOwnerNameDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: localShareRecordNameDefaultsKey)
            UserDefaults.standard.removeObject(forKey: localShareZoneNameDefaultsKey)
            UserDefaults.standard.removeObject(forKey: localShareOwnerNameDefaultsKey)
        }
    }

    private func loadPersistedActiveShareRecordID() -> CKRecord.ID? {
        guard let recordName = UserDefaults.standard.string(forKey: localShareRecordNameDefaultsKey),
              let zoneName = UserDefaults.standard.string(forKey: localShareZoneNameDefaultsKey),
              let ownerName = UserDefaults.standard.string(forKey: localShareOwnerNameDefaultsKey),
              !recordName.isEmpty,
              !zoneName.isEmpty,
              !ownerName.isEmpty else {
            return nil
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        return CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    private var workspaceZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: workspaceZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var workspaceRecordID: CKRecord.ID {
        CKRecord.ID(recordName: workspaceRecordName, zoneID: workspaceZoneID)
    }

    private func ensureWorkspaceZone(completion: @escaping (Result<CKRecordZone.ID, Error>) -> Void) {
        let zone = CKRecordZone(zoneID: workspaceZoneID)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        operation.modifyRecordZonesResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.log("Workspace zone is ready: \(self.workspaceZoneID.zoneName)")
                    completion(.success(self.workspaceZoneID))
                case .failure(let error):
                    self.log("Workspace zone setup failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
        privateDatabase.add(operation)
    }

    struct ParticipantSummary: Identifiable, Equatable {
        let id: String
        let displayName: String
        let emailAddress: String
        let role: String
        let permission: String
        let acceptanceStatus: String
        let userRecordName: String
    }

    struct OwnerTeamSeed {
        let displayName: String
        let status: String
        let title: String
        let cloudKitUserID: String
    }

    func ownerTeamMemberSeed(title: String = "") -> OwnerTeamSeed {
        OwnerTeamSeed(
            displayName: ownerDisplayName,
            status: currentUserIsOwner ? "Owner" : "Active",
            title: title,
            cloudKitUserID: ""
        )
    }


    private func participantRoleText(_ role: CKShare.ParticipantRole) -> String {
        switch role {
        case .owner:
            return "Owner"
        case .privateUser:
            return "Private User"
        case .publicUser:
            return "Public User"
        default:
            return "Unknown"
        }
    }

    private func participantPermissionText(_ permission: CKShare.ParticipantPermission) -> String {
        switch permission {
        case .none:
            return "None"
        case .readOnly:
            return "Read Only"
        case .readWrite:
            return "Read & Write"
        default:
            return "Unknown"
        }
    }

    private func participantAcceptanceStatusText(_ status: CKShare.ParticipantAcceptanceStatus) -> String {
        switch status {
        case .pending:
            return "Invited"
        case .accepted:
            return "Active"
        case .removed:
            return "Removed"
        default:
            return "Unknown"
        }
    }

    private func participantDisplayName(from participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty {
                return formatted
            }
        }

        if let email = participant.userIdentity.lookupInfo?.emailAddress,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }

        return "Unknown Participant"
    }

    private func participantEmailAddress(from participant: CKShare.Participant) -> String {
        participant.userIdentity.lookupInfo?.emailAddress ?? ""
    }

    private func buildParticipantSummary(from participant: CKShare.Participant) -> ParticipantSummary {
        let userRecordName = ""
        let rawDisplayName = participantDisplayName(from: participant)
        let emailAddress = participantEmailAddress(from: participant)
        let isOwner = participant.role == .owner
        let displayName: String

        if isOwner && rawDisplayName == "Unknown Participant" {
            displayName = ownerDisplayName
        } else {
            displayName = rawDisplayName
        }

        let summaryID = !userRecordName.isEmpty
            ? userRecordName
            : "\(displayName)|\(emailAddress)|\(participant.role.rawValue)|\(participant.acceptanceStatus.rawValue)"

        return ParticipantSummary(
            id: summaryID,
            displayName: displayName,
            emailAddress: emailAddress,
            role: participantRoleText(participant.role),
            permission: participantPermissionText(participant.permission),
            acceptanceStatus: participantAcceptanceStatusText(participant.acceptanceStatus),
            userRecordName: userRecordName
        )
    }

    private func syncParticipantSummaries(from share: CKShare) {
        let summaries = share.participants
            .map { buildParticipantSummary(from: $0) }
            .sorted { lhs, rhs in
                if lhs.role == rhs.role {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                if lhs.role == "Owner" { return true }
                if rhs.role == "Owner" { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        participantSummaries = summaries
        log("Participant summaries refreshed: \(summaries.count)")
    }

    func refreshParticipantSummaries(completion: ((Result<[ParticipantSummary], Error>) -> Void)? = nil) {
        if let activeShare {
            syncParticipantSummaries(from: activeShare)
            completion?(.success(participantSummaries))
            return
        }

        guard let activeShareRecordID else {
            participantSummaries = []
            let error = NSError(
                domain: "CloudKitSharingManager",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: "No active workspace share is available for participant refresh"]
            )
            completion?(.failure(error))
            return
        }

        fetchSavedShareURL(for: activeShareRecordID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    if let activeShare = self.activeShare {
                        self.syncParticipantSummaries(from: activeShare)
                        completion?(.success(self.participantSummaries))
                    } else {
                        self.participantSummaries = []
                        let error = NSError(
                            domain: "CloudKitSharingManager",
                            code: -13,
                            userInfo: [NSLocalizedDescriptionKey: "Workspace share was fetched but is not available in memory"]
                        )
                        completion?(.failure(error))
                    }
                case .failure(let error):
                    self.participantSummaries = []
                    completion?(.failure(error))
                }
            }
        }
    }

    func refreshShareStatus() {
        isLoading = true
        lastErrorMessage = ""
        shareStatusText = "Checking workspace share status…"

        ensureWorkspaceZone { [weak self] zoneResult in
            guard let self else { return }

            switch zoneResult {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.clearWorkspaceAndShareState(clearPersistedShareName: true)
                    self.shareStatusText = "Unable to check workspace status"
                    self.inviteStatusText = "Unable to prepare invitations until workspace status is resolved"
                    self.lastErrorMessage = error.localizedDescription
                }

            case .success:
                self.privateDatabase.fetch(withRecordID: self.workspaceRecordID) { [weak self] record, error in
                    DispatchQueue.main.async {
                        guard let self else { return }

                        if let ckError = error as? CKError, ckError.code == .unknownItem {
                            self.clearWorkspaceAndShareState(clearPersistedShareName: true)
                            self.shareStatusText = "No shared workspace found yet"
                            self.inviteStatusText = "Prepare the workspace to enable invitations"
                            self.log("Workspace does not exist yet")
                            return
                        }

                        if let error {
                            self.clearWorkspaceAndShareState(clearPersistedShareName: true)
                            self.shareStatusText = "Unable to check workspace status"
                            self.inviteStatusText = "Unable to prepare invitations until workspace status is resolved"
                            self.lastErrorMessage = error.localizedDescription
                            self.log("Workspace fetch failed: \(error.localizedDescription)")
                            return
                        }

                        guard let record else {
                            self.clearWorkspaceAndShareState(clearPersistedShareName: true)
                            self.shareStatusText = "No shared workspace found yet"
                            self.inviteStatusText = "Prepare the workspace to enable invitations"
                            self.log("Workspace fetch returned no record")
                            return
                        }

                        self.activeWorkspaceRecordID = record.recordID
                        self.currentUserIsOwner = true
                        self.ownerDisplayName = "You"
                        self.lastErrorMessage = ""
                        self.log("Workspace record exists: \(record.recordID.recordName)")
                        self.loadExistingShareIfAvailable(for: record) { _ in }
                    }
                }
            }
        }
    }


    func createWorkspaceIfNeeded(completion: ((Result<Void, Error>) -> Void)? = nil) {
        isLoading = true
        lastErrorMessage = ""
        shareStatusText = "Preparing shared workspace…"
        inviteStatusText = "Preparing team sharing…"

        ensureWorkspaceZone { [weak self] zoneResult in
            guard let self else { return }

            switch zoneResult {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.clearWorkspaceAndShareState(clearPersistedShareName: false)
                    self.shareStatusText = "Unable to create shared workspace"
                    self.inviteStatusText = "Workspace creation failed"
                    self.lastErrorMessage = error.localizedDescription
                    completion?(.failure(error))
                }

            case .success:
                self.privateDatabase.fetch(withRecordID: self.workspaceRecordID) { [weak self] existingRecord, fetchError in
                    DispatchQueue.main.async {
                        guard let self else { return }

                        if let existingRecord {
                            if self.activeShare != nil {
                                self.isLoading = false
                                self.canPresentShareSheet = true
                                self.shareStatusText = "Workspace share is ready"
                                self.inviteStatusText = "Workspace share is ready. Use the Apple share sheet to invite participants."
                                self.log("Workspace and cached share already exist; reusing active share")
                                completion?(.success(()))
                            } else {
                                self.log("Workspace already exists; checking for an existing saved share")
                                self.loadExistingShareIfAvailable(for: existingRecord) { result in
                                    switch result {
                                    case .success:
                                        self.log("Reused saved workspace share")
                                        completion?(.success(()))
                                    case .failure:
                                        self.isLoading = false
                                        self.activeWorkspaceRecordID = existingRecord.recordID
                                        self.activeShareRecordID = nil
                                        self.activeShareURL = nil
                                        self.activeShare = nil
                                        self.canPresentShareSheet = true
                                        self.isInviteLinkReady = false
                                        self.shareStatusText = "Workspace is ready for team sharing"
                                        self.inviteStatusText = "Workspace exists. Open Apple sharing to create or manage the share."
                                        self.log("No reusable saved share found; workspace is ready for UICloudSharingController preparation")
                                        completion?(.success(()))
                                    }
                                }
                            }
                            return
                        }

                        if let fetchError {
                            self.log("Workspace fetch before create failed: \(fetchError.localizedDescription)")
                        }

                        let workspaceRecord = CKRecord(recordType: self.workspaceRecordType, recordID: self.workspaceRecordID)
                        workspaceRecord["name"] = "Armadillo Assistant Team Workspace" as CKRecordValue
                        workspaceRecord["createdAt"] = Date() as CKRecordValue

                        self.privateDatabase.save(workspaceRecord) { [weak self] savedRecord, saveError in
                            DispatchQueue.main.async {
                                guard let self else { return }

                                if let saveError {
                                    self.clearWorkspaceAndShareState(clearPersistedShareName: false)
                                    self.shareStatusText = "Unable to create shared workspace"
                                    self.inviteStatusText = "Workspace creation failed"
                                    self.lastErrorMessage = saveError.localizedDescription
                                    self.log("Workspace save failed: \(saveError.localizedDescription)")
                                    completion?(.failure(saveError))
                                    return
                                }

                                guard let savedRecord else {
                                    let error = NSError(
                                        domain: "CloudKitSharingManager",
                                        code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Workspace save returned no record"]
                                    )
                                    self.clearWorkspaceAndShareState(clearPersistedShareName: false)
                                    self.shareStatusText = "Unable to create shared workspace"
                                    self.inviteStatusText = "Workspace creation failed"
                                    self.lastErrorMessage = error.localizedDescription
                                    self.log(error.localizedDescription)
                                    completion?(.failure(error))
                                    return
                                }

                                self.activeWorkspaceRecordID = savedRecord.recordID
                                self.activeShareRecordID = nil
                                self.activeShareURL = nil
                                self.activeShare = nil
                                self.participantSummaries = []
                                self.canPresentShareSheet = true
                                self.isInviteLinkReady = false
                                self.shareStatusText = "Workspace is ready for team sharing"
                                self.inviteStatusText = "Workspace created. Open Apple sharing to create or manage the share."
                                self.log("Workspace created successfully")
                                completion?(.success(()))
                            }
                        }
                    }
                }
            }
        }
    }

    func ensureWorkspaceAndShare(completion: @escaping (Result<CKShare, Error>) -> Void) {
        if let activeShare {
            canPresentShareSheet = true
            inviteStatusText = "Workspace share is ready. Use the Apple share sheet to invite participants."
            completion(.success(activeShare))
            return
        }

        createWorkspaceIfNeeded { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .success:
                    if let activeShare = self.activeShare {
                        self.canPresentShareSheet = true
                        self.inviteStatusText = "Workspace share is ready. Use the Apple share sheet to invite participants."
                        completion(.success(activeShare))
                    } else if self.activeWorkspaceRecordID != nil {
                        let error = NSError(
                            domain: "CloudKitSharingManager",
                            code: -11,
                            userInfo: [NSLocalizedDescriptionKey: "Workspace exists, but no saved share is currently available. Use the Cloud sharing controller preparation flow to create the share."]
                        )
                        self.canPresentShareSheet = true
                        self.lastErrorMessage = ""
                        completion(.failure(error))
                    } else {
                        let error = NSError(
                            domain: "CloudKitSharingManager",
                            code: -10,
                            userInfo: [NSLocalizedDescriptionKey: "Workspace exists, but no CKShare is available after workspace preparation"]
                        )
                        self.canPresentShareSheet = false
                        self.lastErrorMessage = error.localizedDescription
                        completion(.failure(error))
                    }
                case .failure(let error):
                    self.canPresentShareSheet = false
                    self.lastErrorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    func prepareShareSheetPresentation(completion: ((Result<CKShare, Error>) -> Void)? = nil) {
        ensureWorkspaceAndShare { result in
            completion?(result)
        }
    }

    func prepareInviteLink(completion: ((Result<URL, Error>) -> Void)? = nil) {
        ensureWorkspaceAndShare { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let share):
                    if let shareURL = share.url {
                        self.activeShareURL = shareURL
                        self.isInviteLinkReady = true
                        self.inviteStatusText = "Invitation link is ready"
                        completion?(.success(shareURL))
                    } else if let activeShareRecordID = self.activeShareRecordID {
                        self.fetchSavedShareURL(for: activeShareRecordID) { fetchResult in
                            DispatchQueue.main.async {
                                switch fetchResult {
                                case .success:
                                    if let fetchedURL = self.activeShareURL {
                                        self.isInviteLinkReady = true
                                        self.inviteStatusText = "Invitation link is ready"
                                        completion?(.success(fetchedURL))
                                    } else {
                                        let error = NSError(domain: "CloudKitSharingManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Workspace share exists, but no invitation URL is currently available. The next step is to use UICloudSharingController rather than a raw share URL."])
                                        self.isInviteLinkReady = false
                                        self.inviteStatusText = "Workspace share is ready, but no invitation URL is available yet."
                                        self.lastErrorMessage = error.localizedDescription
                                        completion?(.failure(error))
                                    }
                                case .failure(let error):
                                    self.isInviteLinkReady = false
                                    self.inviteStatusText = "Invitation link is not available"
                                    self.lastErrorMessage = error.localizedDescription
                                    completion?(.failure(error))
                                }
                            }
                        }
                    } else {
                        let error = NSError(domain: "CloudKitSharingManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Workspace share exists, but no invitation URL is currently available. The next step is to use UICloudSharingController rather than a raw share URL."])
                        self.isInviteLinkReady = false
                        self.inviteStatusText = "Workspace share is ready, but no invitation URL is available yet."
                        self.lastErrorMessage = error.localizedDescription
                        completion?(.failure(error))
                    }
                case .failure(let error):
                    self.isInviteLinkReady = false
                    self.inviteStatusText = "Invitation link is not available"
                    self.lastErrorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    func clearError() {
        lastErrorMessage = ""
        currentUserIsOwner = true
        ownerDisplayName = "You"
        if activeShare == nil {
            activeShareRecordID = nil
            persistActiveShareRecordID(nil)
        }
        canPresentShareSheet = (activeWorkspaceRecordID != nil)
        if activeShareURL != nil {
            isInviteLinkReady = true
            inviteStatusText = "Invitation link is ready"
        } else {
            isInviteLinkReady = false
            inviteStatusText = "Prepare the workspace to enable invitations"
        }
    }


    private func fetchSavedShareURL(for shareRecordID: CKRecord.ID,
                                    completion: ((Result<Void, Error>) -> Void)? = nil) {
        privateDatabase.fetch(withRecordID: shareRecordID) { [weak self] record, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.log("Saved share fetch failed: \(error.localizedDescription)")
                    completion?(.failure(error))
                    return
                }

                guard let shareRecord = record as? CKShare else {
                    let error = NSError(
                        domain: "CloudKitSharingManager",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Fetched record was not a CKShare"]
                    )
                    self.log(error.localizedDescription)
                    completion?(.failure(error))
                    return
                }

                self.activeShareRecordID = shareRecord.recordID
                self.activeShareURL = shareRecord.url
                self.activeShare = shareRecord
                self.syncParticipantSummaries(from: shareRecord)
                self.persistActiveShareRecordID(shareRecord.recordID)
                self.canPresentShareSheet = true
                self.isLoading = false
                self.isInviteLinkReady = (shareRecord.url != nil)
                self.inviteStatusText = shareRecord.url == nil
                    ? "Workspace share is ready. Use the Apple share sheet to invite participants."
                    : "Invitation link is ready"
                self.lastErrorMessage = ""
                self.log("Saved share fetch completed")
                completion?(.success(()))
            }
        }
    }

    private func loadExistingShareIfAvailable(for workspaceRecord: CKRecord,
                                              completion: ((Result<CKShare, Error>) -> Void)? = nil) {
        let recordNameFromWorkspace = workspaceRecord["activeShareRecordName"] as? String
        let fallbackRecordID = loadPersistedActiveShareRecordID()
        let shareRecordID: CKRecord.ID?

        if let recordNameFromWorkspace, !recordNameFromWorkspace.isEmpty {
            shareRecordID = CKRecord.ID(recordName: recordNameFromWorkspace, zoneID: workspaceRecord.recordID.zoneID)
        } else {
            shareRecordID = fallbackRecordID
        }

        guard let shareRecordID else {
            clearShareStateForMissingLookup()
            let error = NSError(
                domain: "CloudKitSharingManager",
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: "Workspace exists but has no saved share record name"]
            )
            completion?(.failure(error))
            return
        }

        privateDatabase.fetch(withRecordID: shareRecordID) { [weak self] record, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    self.clearShareStateForMissingLookup()
                    self.persistActiveShareRecordID(nil)
                    workspaceRecord["activeShareRecordName"] = nil
                    self.privateDatabase.save(workspaceRecord) { [weak self] _, saveError in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            if let saveError {
                                self.log("Failed to clear stale workspace share reference: \(saveError.localizedDescription)")
                            } else {
                                self.log("Cleared stale workspace share reference")
                            }
                            self.log("Existing share fetch failed: \(ckError.localizedDescription)")
                            completion?(.failure(ckError))
                        }
                    }
                    return
                }

                if let error {
                    self.clearShareStateForMissingLookup()
                    self.log("Existing share fetch failed: \(error.localizedDescription)")
                    completion?(.failure(error))
                    return
                }

                guard let shareRecord = record as? CKShare else {
                    let error = NSError(
                        domain: "CloudKitSharingManager",
                        code: -8,
                        userInfo: [NSLocalizedDescriptionKey: "Existing workspace share record could not be loaded as CKShare"]
                    )
                    self.clearShareStateForMissingLookup()
                    self.log(error.localizedDescription)
                    completion?(.failure(error))
                    return
                }

                self.persistActiveShareRecordID(shareRecord.recordID)
                self.activeShareRecordID = shareRecord.recordID
                self.activeShareURL = shareRecord.url
                self.activeShare = shareRecord
                self.syncParticipantSummaries(from: shareRecord)
                self.canPresentShareSheet = true
                self.isInviteLinkReady = (shareRecord.url != nil)
                self.isLoading = false
                self.inviteStatusText = shareRecord.url == nil
                    ? "Workspace share is ready. Use the Apple share sheet to invite participants."
                    : "Invitation link is ready"
                self.shareStatusText = "Workspace share is ready"
                self.lastErrorMessage = ""
                self.log("Loaded existing workspace share: \(shareRecord.recordID.recordName)")
                completion?(.success(shareRecord))
            }
        }
    }

    private func clearWorkspaceAndShareState(clearPersistedShareName: Bool) {
        isLoading = false
        activeShareRecordID = nil
        activeShareURL = nil
        activeShare = nil
        participantSummaries = []
        activeWorkspaceRecordID = nil
        canPresentShareSheet = false
        isInviteLinkReady = false
        lastErrorMessage = ""
        if clearPersistedShareName {
            persistActiveShareRecordID(nil)
        }
    }

    private func clearShareStateForMissingLookup() {
        activeShareRecordID = nil
        activeShareURL = nil
        activeShare = nil
        participantSummaries = []
        canPresentShareSheet = false
        isInviteLinkReady = false
        isLoading = false
        inviteStatusText = "Create the workspace share to enable invitations"
        shareStatusText = "Workspace record exists. Prepare workspace sharing to generate an invite link."
    }

    private func log(_ message: String) {
        guard isDebugLoggingEnabled else { return }
        print("[CloudKitSharingManager] \(message)")
    }
}

// End of CloudKitSharingManager.swift
