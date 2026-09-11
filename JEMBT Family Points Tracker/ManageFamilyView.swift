import SwiftData
import SwiftUI

struct ManageFamilyView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @Query(sort: \FamilyInvitation.createdAt, order: .reverse) private var invitations: [FamilyInvitation]
    @State private var showingAddMember = false
    @State private var editingMember: FamilyMember?
    @State private var memberPendingRemoval: FamilyMember?
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
            try appleIDManager.addFamilyMember(
                family: family,
                name: draft.name,
                emailAddress: draft.emailAddress,
                birthDate: draft.birthDate,
                role: draft.role,
                modelContext: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "The family member could not be added: \(error.localizedDescription)"
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

            HStack {
                if let invitation {
                    Text("Invite code: \(invitation.code)")
                        .font(.caption.monospaced().bold())
                    Spacer()
                    ShareLink(
                        item: invitationMessage(code: invitation.code),
                        subject: Text(invitationSubject),
                        message: Text(invitationMessage(code: invitation.code))
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

    private var memberDisplayName: String {
        var name = member.name
        if isCurrentMember {
            name += " (me)"
        }
        if let age = member.currentAge {
            name += " – \(age)"
        } else {
            name += " – No birthdate"
        }
        return name
    }

    private var invitationSubject: String {
        "You're invited to join our allowance family"
    }

    private func invitationMessage(code: String) -> String {
        "You've been invited to join our family in the allowance app. Open the app, sign in, and enter this invitation code: \(code)"
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
    let onSave: (MemberDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MemberDraft
    @State private var validationMessage: String?

    init(
        title: String,
        member: FamilyMember? = nil,
        onSave: @escaping (MemberDraft) -> Void
    ) {
        self.title = title
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
