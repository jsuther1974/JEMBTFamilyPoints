import Contacts
import ContactsUI
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ManageFamilyView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \FamilyInvitation.createdAt, order: .reverse) private var invitations: [FamilyInvitation]
    @State private var showingAddMember = false
    @State private var editingMember: FamilyMember?
    @State private var memberPendingRemoval: FamilyMember?
    @State private var pendingInviteShare: PendingInviteShare?
    @State private var errorMessage: String?

    private var canEdit: Bool {
        appleIDManager.currentMembership?.role.canAdministerFamily == true
    }

    private var familyMembers: [FamilyMember] {
        guard let family = appleIDManager.currentFamily else { return [] }
        var visibleMembers = members.filter { $0.familyID == family.id && $0.isActive }
        if let currentMember = appleIDManager.currentFamilyMember,
           currentMember.isActive,
           !visibleMembers.contains(where: { $0.id == currentMember.id }) {
            visibleMembers.append(currentMember)
        }
        return visibleMembers.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if let family = appleIDManager.currentFamily {
                Section {
                    TextField("My Family", text: familyNameBinding(for: family))
                        .font(.title2.weight(.semibold))
                        .disabled(!canEdit)
                        .accessibilityLabel("Family name")
                        .accessibilityHint(canEdit ? "Family admins can edit this name." : "Only a family admin can edit this name.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if appleIDManager.currentFamilyMember == nil {
                Section {
                    Button("Restore my member profile") {
                        restoreCurrentProfileIfNeeded()
                    }
                } footer: {
                    Text("Use this only if your profile is missing after an older app-data migration.")
                }
            }

            Section {
                if familyMembers.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.3",
                        description: Text(canEdit ? "Add your first family member." : "A family admin can add members.")
                    )
                } else {
                    ForEach(familyMembers) { member in
                        MemberAdministrationRow(
                            member: member,
                            invitation: pendingInvitation(for: member),
                            canEdit: canEdit,
                            isCurrentMember: member.id == appleIDManager.currentFamilyMember?.id,
                            onGenerateCode: { generateCode(for: member) },
                            onEdit: { editingMember = member }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEdit {
                                Button("Remove", role: .destructive) {
                                    memberPendingRemoval = member
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Members")
                    Spacer()
                    if canEdit {
                        Button {
                            showingAddMember = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Add family member")
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle(displayedFamilyName)
        .sheet(isPresented: $showingAddMember) {
            MemberEditorView(title: "Add Family Member") { draft in
                addMember(draft)
            }
        }
        .sheet(item: $editingMember) { member in
            MemberEditorView(title: "Edit Family Member", member: member) { draft in
                update(member, with: draft)
            }
        }
        .sheet(item: $pendingInviteShare) { invite in
            InviteShareSheet(invite: invite)
        }
        .confirmationDialog(
            "Remove family member?",
            isPresented: Binding(
                get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let memberPendingRemoval {
                    deactivate(memberPendingRemoval)
                }
                memberPendingRemoval = nil
            }
        } message: {
            Text("This removes the profile from active use but keeps its historical points records.")
        }
        .task(id: appleIDManager.currentMembership?.id) {
            restoreCurrentProfileIfNeeded()
        }
        .onAppear {
            restoreCurrentProfileIfNeeded()
        }
    }

    private var displayedFamilyName: String {
        let name = appleIDManager.currentFamily?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "My Family" : name
    }

    private func familyNameBinding(for family: AllowanceFamily) -> Binding<String> {
        Binding(
            get: { family.name },
            set: { newValue in
                family.name = newValue
                do {
                    try modelContext.save()
                    errorMessage = nil
                } catch {
                    errorMessage = "The family name could not be saved: \(error.localizedDescription)"
                }
            }
        )
    }

    private func pendingInvitation(for member: FamilyMember) -> FamilyInvitation? {
        invitations.first {
            $0.familyMemberID == member.id &&
            $0.status == .pending &&
            ($0.expiresAt == nil || $0.expiresAt! > .now)
        }
    }

    private func addMember(_ draft: MemberDraft) {
        guard let family = appleIDManager.currentFamily else {
            errorMessage = "No family is selected."
            return
        }
        do {
            let result = try appleIDManager.addFamilyMember(
                family: family,
                name: draft.name,
                emailAddress: draft.emailAddress,
                birthDate: draft.birthDate,
                role: draft.role,
                modelContext: modelContext
            )
            if let invitation = result.invitation {
                pendingInviteShare = PendingInviteShare(
                    invitation: invitation,
                    memberName: result.member.name
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = "The family member could not be added: \(error.localizedDescription)"
        }
    }


private struct PendingInviteShare: Identifiable {
    let id: UUID
    let memberName: String
    let code: String
    let expiresAt: Date?

    init(invitation: FamilyInvitation, memberName: String) {
        self.id = invitation.id
        self.memberName = memberName
        self.code = invitation.code
        self.expiresAt = invitation.expiresAt
    }

    var invitationSubject: String {
        "Join our Family Points group"
    }

    var invitationMessage: String {
        "You've been invited to join our family in Family Points. Open the app and enter this invitation code: \(code)"
    }
}

private struct InviteShareSheet: View {
    let invite: PendingInviteShare
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Invite Ready")
                        .font(.headline)
                    Text("Share this code with \(invite.memberName).")
                        .foregroundStyle(.secondary)
                    if let expiresAt = invite.expiresAt {
                        Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Invitation code") {
                    Text(invite.code)
                        .font(.title3.monospaced().bold())
                        .textSelection(.enabled)
                }

                Section {
                    ShareLink(
                        item: invite.invitationMessage,
                        subject: Text(invite.invitationSubject),
                        message: Text(invite.invitationMessage)
                    ) {
                        Label("Share Invite", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        copyToPasteboard(invite.code)
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Send Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
    private func update(_ member: FamilyMember, with draft: MemberDraft) {
        do {
            try appleIDManager.updateFamilyMember(
                member,
                name: draft.name,
                emailAddress: draft.emailAddress,
                birthDate: draft.birthDate,
                role: draft.role,
                modelContext: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "The family member could not be updated: \(error.localizedDescription)"
        }
    }

    private func restoreCurrentProfileIfNeeded() {
        guard
            let membership = appleIDManager.currentMembership,
            let family = appleIDManager.currentFamily
        else { return }

        do {
            _ = try appleIDManager.ensureProfile(
                for: membership,
                in: family,
                defaultName: membership.role.title,
                modelContext: modelContext
            )
        } catch {
            errorMessage = "Your member profile could not be restored: \(error.localizedDescription)"
        }
    }

    private func deactivate(_ member: FamilyMember) {
        do {
            try appleIDManager.deactivateFamilyMember(member, modelContext: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = "The family member could not be removed: \(error.localizedDescription)"
        }
    }

    private func generateCode(for member: FamilyMember) {
        guard let family = appleIDManager.currentFamily else {
            errorMessage = "No family is selected."
            return
        }
        do {
            _ = try appleIDManager.createInvitation(
                for: family,
                role: FamilyMembershipRole(profileRole: member.role),
                familyMemberID: member.id,
                modelContext: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "The invitation code could not be created: \(error.localizedDescription)"
        }
    }
}

private struct MemberAdministrationRow: View {
    let member: FamilyMember
    let invitation: FamilyInvitation?
    let canEdit: Bool
    let isCurrentMember: Bool
    let onGenerateCode: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(memberDisplayName)
                        .font(.headline)
                    Text(member.role.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !member.isActive {
                    Text("Inactive")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                if canEdit {
                    Button(action: onEdit) {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Edit \(member.name)")
                }
            }

            if let email = member.emailAddress, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isCurrentMember {
                HStack {
                    if let invitation {
                        Text("Invite code: \(invitation.code)")
                            .font(.caption.monospaced().bold())
                        Spacer()
                        ShareLink(
                            item: invitationMessage(invitation),
                            subject: Text(invitationSubject)
                        ) {
                            Label("Share invitation", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Share invitation for \(member.name)")
                    } else if canEdit {
                        Button("Generate invitation code", action: onGenerateCode)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var memberDisplayName: String {
        var name = member.name
        if isCurrentMember {
            name += " (me)"
        }
        if let age = member.currentAge {
            name += " – \(age) \(age == 1 ? "year" : "years") old"
        } else {
            name += " – No birthdate"
        }
        return name
    }

    private var invitationSubject: String {
        "You're invited to join our allowance family"
    }

    private func invitationMessage(_ invitation: FamilyInvitation) -> String {
        var lines = [
            invitationSubject,
            "",
            "Name: \(member.name)",
            "Role: \(member.role.title)"
        ]
        if let email = member.emailAddress, !email.isEmpty {
            lines.append("Email: \(email)")
        }
        if let birthDate = member.birthDate {
            lines.append("Birthdate: \(birthDate.formatted(date: .long, time: .omitted))")
        } else {
            lines.append("Birthdate: Not provided")
        }
        if let age = member.currentAge {
            lines.append("Age: \(age)")
        }
        lines.append("Status: \(member.isActive ? "Active" : "Inactive")")
        lines.append("")
        lines.append("Invitation code: \(invitation.code)")
        if let expiresAt = invitation.expiresAt {
            lines.append("Expires: \(expiresAt.formatted(date: .long, time: .shortened))")
        }
        lines.append("This invitation can be used once.")
        lines.append("")
        lines.append("Open the allowance app, sign in, choose to join a family, and enter the invitation code above.")
        return lines.joined(separator: "\n")
    }
}

private struct MemberDraft {
    var name = ""
    var emailAddress = ""
    var birthDate: Date?
    var role: MemberRole = .child
}

private struct MemberEditorView: View {
    let title: String
    let isAddingMember: Bool
    let onSave: (MemberDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MemberDraft
    @State private var validationMessage: String?
    @State private var showingContactPicker = false
    @State private var contactImportMessage: String?

    init(
        title: String,
        member: FamilyMember? = nil,
        onSave: @escaping (MemberDraft) -> Void
    ) {
        self.title = title
        self.isAddingMember = member == nil
        self.onSave = onSave
        _draft = State(initialValue: MemberDraft(
            name: member?.name ?? "",
            emailAddress: member?.emailAddress ?? "",
            birthDate: member?.birthDate,
            role: member?.role ?? .child
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                if isAddingMember {
                    Section {
                        Button {
                            showingContactPicker = true
                        } label: {
                            Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
                        }
                        if let contactImportMessage {
                            Text(contactImportMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Import a name, first email address, and full birthday when available. Review the details and choose a role before saving.")
                    }
                }

                Section {
                    TextField("Name", text: $draft.name)
                    TextField("Email address (optional)", text: $draft.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Role", selection: $draft.role) {
                        Text("Child").tag(MemberRole.child)
                        Text("Parent").tag(MemberRole.parent)
                        Text("Caregiver").tag(MemberRole.caregiver)
                    }

                    if draft.role == .child || draft.birthDate != nil {
                        DatePicker(
                            draft.role == .child ? "Birthdate" : "Birthday (optional)",
                            selection: birthDateBinding,
                            displayedComponents: .date
                        )
                        .onAppear {
                            if draft.role == .child && draft.birthDate == nil {
                                draft.birthDate = Calendar.current.date(byAdding: .year, value: -10, to: .now) ?? .now
                            }
                        }
                        if draft.role != .child {
                            Button("Remove birthday", role: .destructive) {
                                draft.birthDate = nil
                            }
                        }
                    } else {
                        Button("Add birthday") {
                            draft.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("A birthdate is required for children because starting points are calculated from age. It is optional for parents and caregivers.")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .sheet(isPresented: $showingContactPicker) {
            FamilyMemberContactPicker { contact in
                importContact(contact)
                showingContactPicker = false
            } onCancel: {
                showingContactPicker = false
            }
        }
    }

    private func importContact(_ contact: CNContact) {
        if contact.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]) {
            draft.name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        } else {
            draft.name = ""
        }
        draft.emailAddress = contact.isKeyAvailable(CNContactEmailAddressesKey)
            ? contact.emailAddresses.first.map { $0.value as String } ?? ""
            : ""

        // A month/day-only birthday must never become a fabricated age.
        draft.birthDate = nil
        if contact.isKeyAvailable(CNContactBirthdayKey),
           let birthday = contact.birthday,
           let year = birthday.year, year > 1, year != NSDateComponentUndefined,
           birthday.month != nil, birthday.day != nil {
            let calendar = birthday.calendar ?? Calendar(identifier: .gregorian)
            if let date = calendar.date(from: birthday), date <= .now {
                draft.birthDate = date
            }
        }
        validationMessage = nil
        contactImportMessage = draft.birthDate == nil
            ? "No full birthdate was available. Enter one for a child; it is optional for adults."
            : "Contact details imported. Review them and choose the member’s role before saving."
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.emailAddress = draft.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            validationMessage = "Enter a name."
            return
        }
        guard draft.role != .child || draft.birthDate != nil else {
            validationMessage = "Enter a birthdate for a child profile."
            return
        }
        onSave(draft)
        dismiss()
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { draft.birthDate ?? Calendar.current.date(byAdding: .year, value: -10, to: .now) ?? .now },
            set: { draft.birthDate = $0 }
        )
    }
}

private struct FamilyMemberContactPicker: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> ContactPickerHostController {
        ContactPickerHostController(onSelect: onSelect, onCancel: onCancel)
    }

    func updateUIViewController(_ controller: ContactPickerHostController, context: Context) {}

    // The picker must have its own UIKit presenter. Its automatic dismissal
    // must not target the SwiftUI presentation that owns the member editor.
    final class ContactPickerHostController: UIViewController, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        let onCancel: () -> Void
        private var hasPresentedPicker = false

        init(onSelect: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasPresentedPicker else { return }
            hasPresentedPicker = true
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.predicateForSelectionOfContact = NSPredicate(value: true)
            picker.displayedPropertyKeys = [CNContactEmailAddressesKey, CNContactBirthdayKey]
            picker.modalPresentationStyle = .fullScreen
            present(picker, animated: true)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Finish UIKit's presentation before removing the SwiftUI wrapper.
            picker.dismiss(animated: true) { [self] in
                onSelect(contact)
            }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true) { [self] in
                onCancel()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ManageFamilyView()
            .environment(AppleIDManager())
            .modelContainer(for: [
                AllowanceFamily.self,
                FamilyInvitation.self,
                FamilyMembership.self,
                FamilyMember.self
            ])
    }
}
