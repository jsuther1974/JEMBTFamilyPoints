import AuthenticationServices
import SwiftData
import SwiftUI

struct SignInWithAppleView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query private var memberships: [FamilyMembership]
    @Query private var families: [AllowanceFamily]
    @State private var invitationCode = ""
    @State private var familyName = ""
    @State private var administratorName = ""
    @State private var showingJoin = false
    @State private var showingCreate = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Family Rewards")
                .font(.largeTitle.bold())
            Text("Sign in to create or join a family.")
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleSignIn(result)
            }
            .frame(height: 44)
            .signInWithAppleButtonStyle(.black)

            #if DEBUG
            #if targetEnvironment(simulator)
            Button("Use Simulator Test Account") {
                signInForSimulatorTesting()
            }
            .buttonStyle(.bordered)
            Text("Debug-only shortcut. This does not appear in release builds or on devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #endif
            #endif

            if appleIDManager.currentAppleID != nil {
                Divider()
                Text("What would you like to do?")
                    .font(.headline)

                Button("Join a family with an invitation code") {
                    showingJoin = true
                }
                .buttonStyle(.borderedProminent)

                Button("Create a new family") {
                    showingCreate = true
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingJoin) {
            joinFamilySheet
        }
        .sheet(isPresented: $showingCreate) {
            createFamilySheet
        }
    }

    private var joinFamilySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invitation code", text: $invitationCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Use the private code or link provided by a parent or family owner.")
                }
            }
            .navigationTitle("Join a Family")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingJoin = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { joinFamily() }
                        .disabled(invitationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var createFamilySheet: some View {
        NavigationStack {
            Form {
                TextField("Family name", text: $familyName)
                TextField("Your name", text: $administratorName)
            }
            .navigationTitle("Create a Family")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createFamily() }
                        .disabled(
                            familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            administratorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "The sign-in response was not recognized."
                return
            }
            let appleID = credential.user
            appleIDManager.currentAppleID = appleID
            errorMessage = nil

            if let membership = memberships.first(where: { $0.appleID == appleID }),
               let family = families.first(where: { $0.id == membership.familyID }) {
                appleIDManager.establishSession(
                    appleID: appleID,
                    family: family,
                    membership: membership
                )
                restoreProfile(for: membership, in: family)
            }
        }
    }

    #if DEBUG
    #if targetEnvironment(simulator)
    private func signInForSimulatorTesting() {
        let appleID = ProcessInfo.processInfo.environment["UITEST_APPLE_ID"] ?? "simulator-test-user@local"
        appleIDManager.currentAppleID = appleID
        errorMessage = nil

        if let membership = memberships.first(where: { $0.appleID == appleID }),
           let family = families.first(where: { $0.id == membership.familyID }) {
            appleIDManager.establishSession(
                appleID: appleID,
                family: family,
                membership: membership
            )
            restoreProfile(for: membership, in: family)
        }
    }
    #endif
    #endif

    private func restoreProfile(for membership: FamilyMembership, in family: AllowanceFamily) {
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

    private func joinFamily() {
        guard let appleID = appleIDManager.currentAppleID else { return }
        do {
            try appleIDManager.acceptInvitation(
                code: invitationCode,
                appleID: appleID,
                modelContext: modelContext
            )
            showingJoin = false
            invitationCode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFamily() {
        guard let appleID = appleIDManager.currentAppleID else { return }
        do {
            _ = try appleIDManager.createFamily(
                named: familyName.trimmingCharacters(in: .whitespacesAndNewlines),
                administratorName: administratorName.trimmingCharacters(in: .whitespacesAndNewlines),
                for: appleID,
                modelContext: modelContext
            )
            showingCreate = false
            familyName = ""
            administratorName = ""
        } catch {
            errorMessage = "The family could not be created: \(error.localizedDescription)"
        }
    }
}

struct AppleIDMappingManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppleIDMapping.createdAt, order: .reverse) private var mappings: [AppleIDMapping]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(mappings) { mapping in
                if let member = members.first(where: { $0.id == mapping.familyMemberID }) {
                    VStack(alignment: .leading) {
                        Text(member.name).font(.headline)
                        Text(truncatedAppleID(mapping.appleID))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { delete(mapping) }
                    }
                }
            }
        }
        .navigationTitle("Legacy Mappings")
    }

    private func delete(_ mapping: AppleIDMapping) {
        modelContext.delete(mapping)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func truncatedAppleID(_ value: String) -> String {
        guard value.count > 20 else { return value }
        return "\(value.prefix(12))…\(value.suffix(8))"
    }
}

struct FamilyInvitationView: View {
    @Environment(AppleIDManager.self) private var appleIDManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @State private var role: FamilyMembershipRole = .child
    @State private var selectedMemberID: UUID?
    @State private var generatedCode: String?
    @State private var errorMessage: String?

    private var familyMembers: [FamilyMember] {
        members.filter { $0.familyID == appleIDManager.currentFamily?.id && $0.isActive }
    }

    var body: some View {
        Form {
            Section("Invitation") {
                Picker("Role", selection: $role) {
                    Text("Child").tag(FamilyMembershipRole.child)
                    Text("Parent").tag(FamilyMembershipRole.parent)
                    Text("Caregiver").tag(FamilyMembershipRole.caregiver)
                }

                if role == .child {
                    Picker("Profile (optional)", selection: $selectedMemberID) {
                        Text("Choose later").tag(nil as UUID?)
                        ForEach(familyMembers.filter { $0.role == .child }) { member in
                            Text(member.name).tag(member.id as UUID?)
                        }
                    }
                }

                Button("Generate invitation code") {
                    generateCode()
                }
            }

            if let generatedCode {
                Section("Share this code") {
                    Text(generatedCode)
                        .font(.title2.monospaced().bold())
                        .textSelection(.enabled)
                    Text("This code expires in seven days and can be used once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Invite to Family")
    }

    private func generateCode() {
        guard let family = appleIDManager.currentFamily else {
            errorMessage = "No family is selected."
            return
        }
        do {
            let invitation = try appleIDManager.createInvitation(
                for: family,
                role: role,
                familyMemberID: role == .child ? selectedMemberID : nil,
                modelContext: modelContext
            )
            generatedCode = invitation.code
            errorMessage = nil
        } catch {
            errorMessage = "The invitation could not be created: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SignInWithAppleView()
        .environment(AppleIDManager())
        .modelContainer(for: [AllowanceFamily.self, FamilyInvitation.self, FamilyMembership.self])
}
