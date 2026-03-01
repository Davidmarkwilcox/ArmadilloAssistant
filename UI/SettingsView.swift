//
//  SettingsView.swift
//  ArmadilloAssistant
//
//  Settings hub screen.
//  - Presents top-level navigation into Settings subsections (Profile / Property / Data Management).
//  - Each destination is a lightweight placeholder view for now; we can expand each section later.
//  - This view is intended to remain stable as a "Settings root" while subsections evolve.
//
//  Created by David Wilcox on 3/1/26.
//

import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {

    // MARK: - 1) Debug (default Off)
    private let debugEnabled: Bool = false

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        print("[SettingsView] \(message)")
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
            // We use the branded header instead of the nav bar title.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                debugLog("Appeared")
            }
        }
    }
}

// MARK: - 3) Destination Screens (Placeholders)

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

        // Re-sync local editing state to the persisted values (keeps dirty-tracking accurate)
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

    // MARK: - 5) View
    var body: some View {
        List {
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
        // Hide the default back button so we can intercept navigation-away attempts.
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
                // Revert edits
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
    // NOTE: Property data will ultimately be shared among all users via CloudKit.
    // For the prototype, we store locally so the UI is testable end-to-end.
    @AppStorage("property_name") private var storedPropertyName: String = ""
    @AppStorage("property_shortName") private var storedPropertyShortName: String = ""
    @AppStorage("property_address") private var storedPropertyAddress: String = ""

    @AppStorage("property_cleaningFee") private var storedCleaningFee: Double = 0
    @AppStorage("property_cleaningPayment") private var storedCleaningPayment: Double = 0
    @AppStorage("property_taxRatePercent") private var storedTaxRatePercent: Double = 0

    // Store calendar color as hex for easy persistence
    @AppStorage("property_calendarColorHex") private var storedCalendarColorHex: String = "#B31B1B"

    // MARK: - 2) Editing state
    @State private var propertyName: String = ""
    @State private var propertyShortName: String = ""
    @State private var address: String = ""

    @State private var cleaningFee: Double = 0
    @State private var cleaningPayment: Double = 0
    @State private var taxRatePercent: Double = 0

    @State private var calendarColor: Color = .red

    // Photos are NOT persisted yet (placeholder). We’ll move these to CloudKit-backed assets later.
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

        // Re-sync local editing state to persisted values
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
        // Convert newly selected items to Data.
        // Note: We append; we don’t dedupe yet (prototype).
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

        // Clear picker state to avoid re-processing
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
                // Revert edits (photos remain in-memory; not persisted yet)
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
