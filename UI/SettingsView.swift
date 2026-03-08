//
//  SettingsView.swift
//  ArmadilloAssistant
//
//  File: SettingsView.swift
//  Description: Settings hub screen and settings subsections for profile, property, team sharing,
//  and data management. This file also hosts the Team sharing UI and the UIKit wrapper used to
//  present Apple’s Cloud sharing controller for the shared workspace.
//
//  Created by David Wilcox on 3/1/26.
//

import SwiftUI
import PhotosUI
import UIKit
import CloudKit

struct SettingsView: View {

    // MARK: - 1) Debug (default Off)
    private let debugEnabled: Bool = false

    @StateObject private var sharingManager = CloudKitSharingManager.shared
    @State private var hasPerformedInitialSettingsSessionRefresh: Bool = false

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        print("[SettingsView] \(message)")
    }

    private func performInitialSettingsSessionRefreshIfNeeded() {
        guard !hasPerformedInitialSettingsSessionRefresh else { return }
        hasPerformedInitialSettingsSessionRefresh = true

        sharingManager.refreshShareStatus()
        sharingManager.refreshParticipantSummaries { _ in
            // No local UI state is needed here. This warms the shared manager so
            // TeamSettingsView has the latest workspace + participant data on first open.
        }
    }

    // MARK: - 2) View
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Theme.BrandedHeaderView(title: "Settings")

                List {
                    Section {
                        NavigationLink {
                            ProfileSettingsView()
                        } label: {
                            Label("Profile", systemImage: "person.crop.circle")
                        }

                        NavigationLink {
                            PropertySettingsView()
                        } label: {
                            Label("Property", systemImage: "house")
                        }

                        NavigationLink {
                            TeamSettingsView()
                        } label: {
                            Label("Team", systemImage: "person.3")
                        }

                        NavigationLink {
                            DataManagementSettingsView()
                        } label: {
                            Label("Data Management", systemImage: "tray.2")
                        }
                    } footer: {
                        Text("Prototype navigation only. Content is placeholder and will expand over time.")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                debugLog("Appeared")
                performInitialSettingsSessionRefreshIfNeeded()
            }
        }
    }
}

// MARK: - 3) Destination Screens

private struct TeamSettingsView: View {

    struct TeamMember: Identifiable {
        let id: String
        var name: String
        var email: String
        var title: String
        var status: String   // Derived from CloudKit share participant acceptance state
        var cloudKitUserID: String
        var canResendInvite: Bool
        var canRecallInvite: Bool
        var canRemoveAccess: Bool
        var isOwnerRow: Bool
    }

    @State private var members: [TeamMember] = []
    @State private var inviteStatusMessage: String = "Prepare the workspace to enable invitations"
    @State private var pendingInviteLink: String = ""
    @State private var shareSheetStatusMessage: String = "Prepare the workspace to enable invite presentation"
    @State private var isShowingCloudSharingController: Bool = false
    @State private var shareToPresent: CKShare?
    @StateObject private var sharingManager = CloudKitSharingManager.shared

    private func seedOwnerRowIfNeeded() {
        guard !members.contains(where: { $0.isOwnerRow }) else { return }

        let ownerSeed = sharingManager.ownerTeamMemberSeed()
        members.insert(
            TeamMember(
                id: "owner-local-row",
                name: ownerSeed.displayName,
                email: "",
                title: ownerSeed.title,
                status: ownerSeed.status,
                cloudKitUserID: ownerSeed.cloudKitUserID,
                canResendInvite: false,
                canRecallInvite: false,
                canRemoveAccess: false,
                isOwnerRow: true
            ),
            at: 0
        )
    }

    private func refreshMembersFromShare() {
        let existingTitles = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.title) })

        let refreshedMembers = sharingManager.participantSummaries.map { participant in
            let status = participant.acceptanceStatus
            let isOwner = participant.role == "Owner"
            let resolvedEmail = participant.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            return TeamMember(
                id: participant.id,
                name: resolvedName.isEmpty ? "Unknown Participant" : resolvedName,
                email: resolvedEmail,
                title: existingTitles[participant.id] ?? "",
                status: status,
                cloudKitUserID: participant.userRecordName,
                canResendInvite: status == "Invited" && !isOwner,
                canRecallInvite: status == "Invited" && !isOwner,
                canRemoveAccess: status == "Active" && !isOwner,
                isOwnerRow: isOwner
            )
        }

        members = refreshedMembers

        if members.isEmpty {
            seedOwnerRowIfNeeded()
        }
    }


    private func refreshWorkspaceAndParticipantsAfterSharingUI() {
        sharingManager.refreshShareStatus()
        inviteStatusMessage = sharingManager.inviteStatusText
        shareSheetStatusMessage = sharingManager.canPresentShareSheet
            ? "Workspace share is ready for Apple share sheet presentation."
            : "Prepare the workspace to enable invite presentation"
        pendingInviteLink = sharingManager.activeShareURL?.absoluteString ?? ""

        sharingManager.refreshParticipantSummaries { _ in
            DispatchQueue.main.async {
                inviteStatusMessage = sharingManager.inviteStatusText
                shareSheetStatusMessage = sharingManager.canPresentShareSheet
                    ? "Workspace share is ready for Apple share sheet presentation."
                    : "Prepare the workspace to enable invite presentation"
                pendingInviteLink = sharingManager.activeShareURL?.absoluteString ?? ""
                refreshMembersFromShare()
            }
        }
    }

    private func manageTeamSharing() {
        if sharingManager.activeWorkspaceRecordID != nil && sharingManager.activeShare == nil {
            shareSheetStatusMessage = "Workspace is ready. Opening sharing controller…"
            inviteStatusMessage = "Workspace is ready. Opening sharing controller…"
            shareToPresent = nil
            isShowingCloudSharingController = true
            return
        }

        inviteStatusMessage = "Preparing sharing controller…"

        sharingManager.prepareShareSheetPresentation { result in
            switch result {
            case .success(let share):
                DispatchQueue.main.async {
                    shareSheetStatusMessage = "Workspace share is ready. Opening sharing controller…"
                    inviteStatusMessage = "Workspace share is ready. Opening sharing controller…"
                    pendingInviteLink = share.url?.absoluteString ?? "Cloud sharing controller ready"
                    shareToPresent = share
                    isShowingCloudSharingController = true
                }

            case .failure:
                DispatchQueue.main.async {
                    if sharingManager.activeWorkspaceRecordID != nil {
                        shareSheetStatusMessage = "Workspace is ready. Opening sharing controller…"
                        inviteStatusMessage = "Workspace is ready. Opening sharing controller…"
                        shareToPresent = nil
                        isShowingCloudSharingController = true
                    } else {
                        pendingInviteLink = sharingManager.activeShareURL?.absoluteString ?? pendingInviteLink
                        shareSheetStatusMessage = "Unable to prepare sharing controller."
                        inviteStatusMessage = "Unable to prepare team sharing."
                    }
                }
            }
        }
    }

    private func resendInvite(for memberID: String) {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        guard members[index].status == "Invited" else { return }

        let targetEmail = members[index].email

        if sharingManager.activeWorkspaceRecordID != nil && sharingManager.activeShare == nil {
            shareSheetStatusMessage = "Workspace is ready. Opening sharing controller to re-invite \(targetEmail)…"
            inviteStatusMessage = "Workspace is ready. Opening sharing controller to re-invite \(targetEmail)…"
            shareToPresent = nil
            isShowingCloudSharingController = true
            return
        }

        inviteStatusMessage = "Preparing sharing controller for \(targetEmail)…"

        sharingManager.prepareShareSheetPresentation { result in
            switch result {
            case .success(let share):
                DispatchQueue.main.async {
                    shareSheetStatusMessage = "Workspace share is ready. Opening sharing controller to re-invite \(targetEmail)…"
                    inviteStatusMessage = "Workspace share is ready. Opening sharing controller to re-invite \(targetEmail)…"
                    pendingInviteLink = share.url?.absoluteString ?? "Cloud sharing controller ready"
                    shareToPresent = share
                    isShowingCloudSharingController = true
                }

            case .failure:
                DispatchQueue.main.async {
                    if sharingManager.activeWorkspaceRecordID != nil {
                        shareSheetStatusMessage = "Workspace is ready. Opening sharing controller to re-invite \(targetEmail)…"
                        inviteStatusMessage = "Workspace is ready. Opening sharing controller to re-invite \(targetEmail)…"
                        shareToPresent = nil
                        isShowingCloudSharingController = true
                    } else {
                        pendingInviteLink = sharingManager.activeShareURL?.absoluteString ?? pendingInviteLink
                        shareSheetStatusMessage = "Unable to prepare sharing controller."
                        inviteStatusMessage = "Unable to refresh invitation."
                    }
                }
            }
        }
    }

    private func recallInvite(for memberID: String) {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        guard members[index].status == "Invited" else { return }

        // Placeholder only. Later this will remove the pending CloudKit participant/share invitation.
        members.remove(at: index)
    }

    private func removeAccess(for memberID: String) {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        guard members[index].status == "Active", !members[index].isOwnerRow else { return }

        // Placeholder only. Later this will remove the accepted CloudKit participant from the share.
        members.remove(at: index)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sharingManager.shareStatusText)

                    if let shareURL = sharingManager.activeShareURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Share Link")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(shareURL.absoluteString)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    if !sharingManager.lastErrorMessage.isEmpty {
                        if sharingManager.activeShareRecordID != nil {
                            Text("Workspace share exists, but the invitation link is not available yet. Refresh workspace status and try again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(sharingManager.lastErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Text(sharingManager.inviteStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !shareSheetStatusMessage.isEmpty {
                        Text(shareSheetStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        sharingManager.createWorkspaceIfNeeded()
                    } label: {
                        Label("Prepare Team Workspace", systemImage: "person.3.sequence")
                    }
                    .disabled(sharingManager.isLoading)

                    Button {
                        sharingManager.refreshShareStatus()
                    } label: {
                        Label("Refresh Workspace Status", systemImage: "arrow.clockwise")
                    }
                    .disabled(sharingManager.isLoading)

                }
            } header: {
                Text("Workspace")
            } footer: {
                Text("Prepare the shared team workspace before managing participants. Once prepared, use Manage Team Sharing to open Apple’s sharing controller.")
            }

            Section {
                if !inviteStatusMessage.isEmpty {
                    Text(inviteStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !pendingInviteLink.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Share Status")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(pendingInviteLink)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Button {
                    manageTeamSharing()
                } label: {
                    Label("Manage Team Sharing", systemImage: "person.badge.key")
                }

            } header: {
                Text("Team Sharing")
            } footer: {
                Text("Use Manage Team Sharing to open Apple’s sharing controller and add or manage participants for the shared workspace.")
            }

            Section {
                if members.isEmpty {
                    Text("No team members yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($members) { $member in
                        VStack(alignment: .leading, spacing: 8) {

                            Text(member.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? member.name : member.email)
                                .font(.headline)

                            HStack {
                                Text("Status:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(member.status)
                                    .font(.caption)
                            }

                            if !member.isOwnerRow, !member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack {
                                    Text("Name:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(member.name)
                                        .font(.caption)
                                }
                            }

                            if member.isOwnerRow {
                                Text("Workspace Owner")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !member.cloudKitUserID.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("CloudKit User ID")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(member.cloudKitUserID)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                            }

                            TextField("Title (Manager, Owner, Cleaner, etc.)", text: $member.title)
                                .textInputAutocapitalization(.words)

                            HStack(spacing: 12) {
                                if member.canResendInvite {
                                    Button("Resend") {
                                        resendInvite(for: member.id)
                                    }
                                    .font(.caption)
                                }

                                if member.canRecallInvite {
                                    Button("Recall", role: .destructive) {
                                        recallInvite(for: member.id)
                                    }
                                    .font(.caption)
                                }

                                if member.canRemoveAccess {
                                    Button("Remove Access", role: .destructive) {
                                        removeAccess(for: member.id)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Team Members")
            } footer: {
                Text("The workspace owner is included automatically. Titles are informational and help identify responsibilities within the team. Invited members can be re-invited or recalled; active members can have access removed. A CloudKit User ID will be stored once a participant accepts and is linked to the shared workspace.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Team")
        .onAppear {
            inviteStatusMessage = sharingManager.inviteStatusText
            shareSheetStatusMessage = sharingManager.canPresentShareSheet
                ? "Workspace share is ready for Apple share sheet presentation."
                : "Prepare the workspace to enable invite presentation"
            pendingInviteLink = sharingManager.activeShareURL?.absoluteString ?? ""
            refreshMembersFromShare()
        }
        .onReceive(sharingManager.$participantSummaries) { _ in
            inviteStatusMessage = sharingManager.inviteStatusText
            shareSheetStatusMessage = sharingManager.canPresentShareSheet
                ? "Workspace share is ready for Apple share sheet presentation."
                : "Prepare the workspace to enable invite presentation"
            pendingInviteLink = sharingManager.activeShareURL?.absoluteString ?? ""
            refreshMembersFromShare()
        }
        .sheet(isPresented: $isShowingCloudSharingController, onDismiss: {
            refreshWorkspaceAndParticipantsAfterSharingUI()
        }) {
            CloudSharingControllerSheet(share: shareToPresent)
        }
    }
}

private struct ProfileSettingsView: View {

    // MARK: - 1) Persistence (placeholder)
    // NOTE: For v1 this is local-only and unique per device/user.
    // Later we can replace this with CloudKit-backed user profile data.
    @AppStorage("profile_firstName") private var storedFirstName: String = ""
    @AppStorage("profile_lastName") private var storedLastName: String = ""
    @AppStorage("profile_email") private var storedEmail: String = ""
    @AppStorage("profile_phone") private var storedPhone: String = ""
    @AppStorage("profile_photoBase64") private var storedProfilePhotoBase64: String = ""

    // MARK: - 2) Editing state
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var profilePhotoItem: PhotosPickerItem? = nil
    @State private var profilePhotoData: Data? = nil

    @State private var isInitialized: Bool = false
    @State private var showUnsavedAlert: Bool = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - 3A) CloudKit User Identity
    @State private var cloudKitStatusText: String = "Checking iCloud account…"
    @State private var cloudKitRecordName: String = ""
    @State private var isLoadingCloudKitIdentity: Bool = false

    // MARK: - 3) Computed
    private var hasUnsavedChanges: Bool {
        guard isInitialized else { return false }
        return firstName != storedFirstName
            || lastName != storedLastName
            || email != storedEmail
            || phone != storedPhone
            || (profilePhotoData?.base64EncodedString() ?? "") != storedProfilePhotoBase64
    }

    // MARK: - 4) Actions
    private func loadFromStorageIfNeeded() {
        guard !isInitialized else { return }
        firstName = storedFirstName
        lastName = storedLastName
        email = storedEmail
        phone = storedPhone
        if storedProfilePhotoBase64.isEmpty {
            profilePhotoData = nil
        } else {
            profilePhotoData = Data(base64Encoded: storedProfilePhotoBase64)
        }
        isInitialized = true
    }

    private func save() {
        storedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        storedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        storedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        storedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profilePhotoData {
            storedProfilePhotoBase64 = profilePhotoData.base64EncodedString()
        } else {
            storedProfilePhotoBase64 = ""
        }

        firstName = storedFirstName
        lastName = storedLastName
        email = storedEmail
        phone = storedPhone
        if storedProfilePhotoBase64.isEmpty {
            profilePhotoData = nil
        } else {
            profilePhotoData = Data(base64Encoded: storedProfilePhotoBase64)
        }
    }

    private func backTapped() {
        if hasUnsavedChanges {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }

    private func loadCloudKitIdentity() {
        guard !isLoadingCloudKitIdentity else { return }
        isLoadingCloudKitIdentity = true
        cloudKitStatusText = "Checking iCloud account…"

        let container = CKContainer(identifier: CloudKitSharingManager.containerIdentifier)
        container.accountStatus { status, error in
            if let error {
                DispatchQueue.main.async {
                    cloudKitStatusText = "Unable to verify iCloud account"
                    cloudKitRecordName = ""
                    isLoadingCloudKitIdentity = false
                    print("[ProfileSettingsView] CloudKit account status error: \(error.localizedDescription)")
                }
                return
            }

            switch status {
            case .available:
                container.fetchUserRecordID { recordID, recordError in
                    DispatchQueue.main.async {
                        if let recordError {
                            cloudKitStatusText = "Signed into iCloud, but user ID could not be fetched"
                            cloudKitRecordName = ""
                            print("[ProfileSettingsView] CloudKit user record fetch error: \(recordError.localizedDescription)")
                        } else if let recordID {
                            cloudKitStatusText = "Signed in with iCloud"
                            cloudKitRecordName = recordID.recordName
                        } else {
                            cloudKitStatusText = "Signed into iCloud, but no user ID was returned"
                            cloudKitRecordName = ""
                        }
                        isLoadingCloudKitIdentity = false
                    }
                }

            case .noAccount:
                DispatchQueue.main.async {
                    cloudKitStatusText = "No iCloud account is signed in on this device"
                    cloudKitRecordName = ""
                    isLoadingCloudKitIdentity = false
                }

            case .restricted:
                DispatchQueue.main.async {
                    cloudKitStatusText = "iCloud account access is restricted on this device"
                    cloudKitRecordName = ""
                    isLoadingCloudKitIdentity = false
                }

            case .couldNotDetermine:
                DispatchQueue.main.async {
                    cloudKitStatusText = "Unable to determine iCloud account status"
                    cloudKitRecordName = ""
                    isLoadingCloudKitIdentity = false
                }

            case .temporarilyUnavailable:
                DispatchQueue.main.async {
                    cloudKitStatusText = "iCloud is temporarily unavailable"
                    cloudKitRecordName = ""
                    isLoadingCloudKitIdentity = false
                }

            @unknown default:
                DispatchQueue.main.async {
                    cloudKitStatusText = "Unknown iCloud account status"
                    cloudKitRecordName = ""
                    isLoadingCloudKitIdentity = false
                }
            }
        }
    }

    // MARK: - 5) View
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    let displayName = [storedFirstName, storedLastName]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    if !displayName.isEmpty {
                        Text("Signed in as: \(displayName)")
                    } else {
                        Text(cloudKitStatusText)
                    }

                    if !cloudKitRecordName.isEmpty {
                        DisclosureGroup("Advanced") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CloudKit User ID")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(cloudKitRecordName)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 4)
                        }
                    }

                    Button {
                        loadCloudKitIdentity()
                    } label: {
                        Label("Refresh iCloud Status", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingCloudKitIdentity)
                }
            } header: {
                Text("Signed In")
            } footer: {
                Text("Your display name comes from your profile fields. The CloudKit User ID is an internal identifier used for attribution and synchronization.")
            }

            Section {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)

                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            } header: {
                Text("Profile")
            } footer: {
                Text("This information is unique to each user. For now it’s stored locally as placeholder data.")
            }

            Section {
                HStack(spacing: 12) {
                    Group {
                        if let data = profilePhotoData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $profilePhotoItem, matching: .images, photoLibrary: .shared()) {
                            Label("Choose Photo", systemImage: "photo")
                        }

                        Button(role: .destructive) {
                            profilePhotoData = nil
                            profilePhotoItem = nil
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                        .disabled(profilePhotoData == nil)
                    }
                }
            } header: {
                Text("Profile Picture")
            } footer: {
                Text("Stored locally as placeholder data for now.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profile")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    backTapped()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(!hasUnsavedChanges)
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save") {
                save()
                dismiss()
            }
            Button("Discard Changes", role: .destructive) {
                firstName = storedFirstName
                lastName = storedLastName
                email = storedEmail
                phone = storedPhone
                if storedProfilePhotoBase64.isEmpty {
                    profilePhotoData = nil
                } else {
                    profilePhotoData = Data(base64Encoded: storedProfilePhotoBase64)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved profile changes. Save before leaving?")
        }
        .onAppear {
            loadFromStorageIfNeeded()
            loadCloudKitIdentity()
        }
        .task(id: profilePhotoItem?.itemIdentifier) {
            guard let item = profilePhotoItem else { return }
            if let data = try? await item.loadTransferable(type: Data.self) {
                profilePhotoData = data
            }
        }
    }
}

private struct PropertySettingsView: View {

    // MARK: - 1) Persistence (placeholder)
    @AppStorage("property_name") private var storedPropertyName: String = ""
    @AppStorage("property_shortName") private var storedPropertyShortName: String = ""
    @AppStorage("property_address") private var storedPropertyAddress: String = ""

    @AppStorage("property_cleaningFee") private var storedCleaningFee: Double = 0
    @AppStorage("property_cleaningPayment") private var storedCleaningPayment: Double = 0
    @AppStorage("property_taxRatePercent") private var storedTaxRatePercent: Double = 0

    @AppStorage("property_calendarColorHex") private var storedCalendarColorHex: String = "#B31B1B"

    // MARK: - 2) Editing state
    @State private var propertyName: String = ""
    @State private var propertyShortName: String = ""
    @State private var address: String = ""

    @State private var cleaningFee: Double = 0
    @State private var cleaningPayment: Double = 0
    @State private var taxRatePercent: Double = 0

    @State private var calendarColor: Color = .red

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photos: [PropertyPhoto] = []
    @State private var defaultPhotoID: UUID? = nil

    @State private var isInitialized: Bool = false
    @State private var showUnsavedAlert: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // MARK: - 3) Models
    private struct PropertyPhoto: Identifiable {
        let id: UUID
        let imageData: Data

        var uiImage: UIImage? { UIImage(data: imageData) }
    }

    // MARK: - 4) Computed
    private var hasUnsavedChanges: Bool {
        guard isInitialized else { return false }
        return propertyName != storedPropertyName
            || propertyShortName != storedPropertyShortName
            || address != storedPropertyAddress
            || cleaningFee != storedCleaningFee
            || cleaningPayment != storedCleaningPayment
            || taxRatePercent != storedTaxRatePercent
            || calendarColor.toHexString() != storedCalendarColorHex
    }

    private var mapsURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var comps = URLComponents(string: "http://maps.apple.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return comps.url
    }

    // MARK: - 5) Actions
    private func loadFromStorageIfNeeded() {
        guard !isInitialized else { return }

        propertyName = storedPropertyName
        propertyShortName = storedPropertyShortName
        address = storedPropertyAddress

        cleaningFee = storedCleaningFee
        cleaningPayment = storedCleaningPayment
        taxRatePercent = storedTaxRatePercent

        calendarColor = Color(hex: storedCalendarColorHex) ?? .red

        isInitialized = true
    }

    private func save() {
        storedPropertyName = propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        storedPropertyShortName = propertyShortName.trimmingCharacters(in: .whitespacesAndNewlines)
        storedPropertyAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        storedCleaningFee = cleaningFee
        storedCleaningPayment = cleaningPayment
        storedTaxRatePercent = taxRatePercent

        storedCalendarColorHex = calendarColor.toHexString()

        propertyName = storedPropertyName
        propertyShortName = storedPropertyShortName
        address = storedPropertyAddress

        cleaningFee = storedCleaningFee
        cleaningPayment = storedCleaningPayment
        taxRatePercent = storedTaxRatePercent

        calendarColor = Color(hex: storedCalendarColorHex) ?? calendarColor
    }

    private func backTapped() {
        if hasUnsavedChanges {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }

    private func setDefaultPhoto(_ photo: PropertyPhoto) {
        defaultPhotoID = photo.id
    }

    private func removePhoto(_ photo: PropertyPhoto) {
        photos.removeAll { $0.id == photo.id }
        if defaultPhotoID == photo.id {
            defaultPhotoID = photos.first?.id
        }
    }

    private func loadSelectedPhotos() async {
        var newPhotos: [PropertyPhoto] = []

        for item in selectedPhotoItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                newPhotos.append(PropertyPhoto(id: UUID(), imageData: data))
            }
        }

        if !newPhotos.isEmpty {
            photos.append(contentsOf: newPhotos)
            if defaultPhotoID == nil {
                defaultPhotoID = photos.first?.id
            }
        }

        selectedPhotoItems = []
    }

    // MARK: - 6) View
    var body: some View {
        List {

            Section {
                TextField("Property Name", text: $propertyName)
                    .textInputAutocapitalization(.words)

                TextField("Property Short Name", text: $propertyShortName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Identity")
            } footer: {
                Text("Short name is used where space is limited (e.g., calendar tiles).")
            }

            Section {
                TextField("Address", text: $address, axis: .vertical)
                    .textInputAutocapitalization(.words)

                Button {
                    if let url = mapsURL { openURL(url) }
                } label: {
                    Label("Open in Maps", systemImage: "map")
                }
                .disabled(mapsURL == nil)
            } header: {
                Text("Address")
            } footer: {
                Text("Address will be linkable to the default Maps app.")
            }

            Section {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 12,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                }

                if photos.isEmpty {
                    Text("No photos added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(photos) { photo in
                                VStack(spacing: 6) {
                                    if let img = photo.uiImage {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 96, height: 72)
                                            .clipped()
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(defaultPhotoID == photo.id ? Theme.Colors.crimson : Color.clear, lineWidth: 3)
                                            )
                                            .onTapGesture {
                                                setDefaultPhoto(photo)
                                            }
                                    } else {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 96, height: 72)
                                    }

                                    HStack(spacing: 10) {
                                        Button("Default") {
                                            setDefaultPhoto(photo)
                                        }
                                        .font(.caption)
                                        .disabled(defaultPhotoID == photo.id)

                                        Button(role: .destructive) {
                                            removePhoto(photo)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .font(.caption)
                                    }

                                    if defaultPhotoID == photo.id {
                                        Text("Thumbnail")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("Tap an image to set it as the default thumbnail. Photo persistence is placeholder for now.")
            }
            .task(id: selectedPhotoItems.count) {
                if !selectedPhotoItems.isEmpty {
                    await loadSelectedPhotos()
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleaning Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$", value: $cleaningFee, format: .number)
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleaning Payment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$", value: $cleaningPayment, format: .number)
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tax Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("%", value: $taxRatePercent, format: .number)
                        .keyboardType(.decimalPad)
                }
            } header: {
                Text("Fees & Taxes")
            } footer: {
                Text("All values are placeholders and will be used for reservation calculations later.")
            }

            Section {
                ColorPicker("Calendar Color", selection: $calendarColor, supportsOpacity: false)
            } header: {
                Text("Calendar")
            } footer: {
                Text("This color will be used for calendar blocks and labels for this property.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Property")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    backTapped()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(!hasUnsavedChanges)
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save") {
                save()
                dismiss()
            }
            Button("Discard Changes", role: .destructive) {
                propertyName = storedPropertyName
                propertyShortName = storedPropertyShortName
                address = storedPropertyAddress
                cleaningFee = storedCleaningFee
                cleaningPayment = storedCleaningPayment
                taxRatePercent = storedTaxRatePercent
                calendarColor = Color(hex: storedCalendarColorHex) ?? calendarColor
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved property changes. Save before leaving?")
        }
        .onAppear {
            loadFromStorageIfNeeded()
        }
    }
}

private struct DataManagementSettingsView: View {
    var body: some View {
        List {
            Section("Export") {
                Button {
                    // Placeholder
                } label: {
                    Label("Export reservations to CSV", systemImage: "square.and.arrow.up")
                }
            }

            Section("Import") {
                Button {
                    // Placeholder
                } label: {
                    Label("Import reservations", systemImage: "square.and.arrow.down")
                }
            }

            Section {
                Button(role: .destructive) {
                    // Placeholder
                } label: {
                    Label("Delete all reservation data", systemImage: "trash")
                }
            } header: {
                Text("Deletion")
            } footer: {
                Text("Prototype only — we’ll add confirmation and actual data operations later.")
            }
        }
        .navigationTitle("Data Management")
    }
}

private struct CloudSharingControllerSheet: UIViewControllerRepresentable {
    let share: CKShare?
    private let debugEnabled: Bool = true

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        print("[CloudSharingControllerSheet] \(message)")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(debugEnabled: debugEnabled)
    }

    func makeUIViewController(context: Context) -> HostViewController {
        debugLog("makeUIViewController called")
        let controller = HostViewController()
        controller.debugEnabled = debugEnabled
        controller.coordinator = context.coordinator
        controller.share = share
        return controller
    }

    func updateUIViewController(_ uiViewController: HostViewController, context: Context) {
        debugLog("updateUIViewController called")
        uiViewController.debugEnabled = debugEnabled
        uiViewController.coordinator = context.coordinator
        uiViewController.share = share
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private let debugEnabled: Bool

        init(debugEnabled: Bool) {
            self.debugEnabled = debugEnabled
        }

        func debugLog(_ message: String) {
            guard debugEnabled else { return }
            print("[CloudSharingControllerSheet] \(message)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            debugLog("itemTitle requested")
            return "Armadillo Assistant Team"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            debugLog("itemThumbnailData requested")
            return nil
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            debugLog("Failed to save share: \(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            debugLog("Share saved successfully")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            debugLog("Sharing stopped")
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            debugLog("Sharing controller dismissed")
        }
    }

    final class HostViewController: UIViewController {
        var debugEnabled: Bool = true
        weak var coordinator: Coordinator?
        var share: CKShare?
        private var hasPresentedSharingController = false

        private func debugLog(_ message: String) {
            guard debugEnabled else { return }
            print("[CloudSharingControllerSheet] \(message)")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            debugLog("Host view did load")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            debugLog("Host view did appear")
            presentSharingControllerIfNeeded()
        }

        private func presentSharingControllerIfNeeded() {
            guard !hasPresentedSharingController else {
                debugLog("Host view already presented sharing controller")
                return
            }
            guard presentedViewController == nil else {
                debugLog("Host view already has a presented view controller")
                return
            }
            guard let coordinator else {
                debugLog("Host view missing coordinator")
                return
            }

            hasPresentedSharingController = true
            let container = CKContainer(identifier: CloudKitSharingManager.containerIdentifier)
            let sharingController: UICloudSharingController

            if let share {
                debugLog("Presenting sharing controller for existing share \(share.recordID.recordName)")
                sharingController = UICloudSharingController(share: share, container: container)
            } else {
                debugLog("Presenting sharing controller with preparation handler")
                sharingController = UICloudSharingController { _, preparationCompletionHandler in
                    print("[CloudSharingControllerSheet] Preparation handler entered")
                    let zoneID = CKRecordZone.ID(zoneName: "TeamWorkspaceZone", ownerName: CKCurrentUserDefaultName)
                    let workspaceID = CKRecord.ID(recordName: "primary-workspace", zoneID: zoneID)
                    let container = CKContainer(identifier: CloudKitSharingManager.containerIdentifier)
                    let privateDatabase = container.privateCloudDatabase
                    print("[CloudSharingControllerSheet] Preparation handler using workspace ID: \(workspaceID.recordName) in zone \(zoneID.zoneName)")
                    print("[CloudSharingControllerSheet] Preparation handler fetching workspace record from CloudKit")

                    privateDatabase.fetch(withRecordID: workspaceID) { record, error in
                        if let error {
                            DispatchQueue.main.async {
                                print("[CloudSharingControllerSheet] Preparation fetch failed: \(error.localizedDescription)")
                                preparationCompletionHandler(nil, container, error)
                            }
                            return
                        }

                        guard let workspaceRecord = record else {
                            let error = NSError(
                                domain: "CloudSharingControllerSheet",
                                code: -100,
                                userInfo: [NSLocalizedDescriptionKey: "Workspace record was not found during share preparation"]
                            )
                            DispatchQueue.main.async {
                                print("[CloudSharingControllerSheet] Preparation fetch returned no workspace record")
                                preparationCompletionHandler(nil, container, error)
                            }
                            return
                        }

                        print("[CloudSharingControllerSheet] Preparation handler fetched workspace record successfully")
                        let share = CKShare(rootRecord: workspaceRecord)
                        share[CKShare.SystemFieldKey.title] = "Armadillo Assistant Team" as CKRecordValue
                        print("[CloudSharingControllerSheet] Preparation handler created CKShare \(share.recordID.recordName)")
                        let operation = CKModifyRecordsOperation(recordsToSave: [workspaceRecord, share], recordIDsToDelete: nil)
                        print("[CloudSharingControllerSheet] Preparation handler submitting workspace+share save operation")
                        operation.modifyRecordsResultBlock = { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    print("[CloudSharingControllerSheet] Preparation handler saved share \(share.recordID.recordName)")
                                    preparationCompletionHandler(share, container, nil)
                                case .failure(let error):
                                    print("[CloudSharingControllerSheet] Preparation handler failed: \(error.localizedDescription)")
                                    preparationCompletionHandler(nil, container, error)
                                }
                            }
                        }
                        privateDatabase.add(operation)
                    }
                }
            }

            sharingController.delegate = coordinator
            sharingController.availablePermissions = [.allowReadWrite, .allowPrivate]
            sharingController.presentationController?.delegate = coordinator
            coordinator.debugLog("About to present UICloudSharingController")
            present(sharingController, animated: true)
        }
    }
}

// MARK: - 5) Color helpers (for simple local persistence)

private extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6,
              let intVal = Int(sanitized, radix: 16) else { return nil }

        let r = CGFloat((intVal >> 16) & 0xFF) / 255.0
        let g = CGFloat((intVal >> 8) & 0xFF) / 255.0
        let b = CGFloat(intVal & 0xFF) / 255.0
        self = Color(red: Double(r), green: Double(g), blue: Double(b))
    }

    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)

        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

#Preview {
    SettingsView()
}

// End of SettingsView.swift
