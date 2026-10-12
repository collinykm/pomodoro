import SwiftUI

struct TasksView: View {
    @Environment(TimerEngine.self) private var engine
    @State private var service = GoogleTasksService.shared
    @State private var newTask = ""

    private let settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TASKS")
                            .font(TypeStyle.display(36))
                            .tracking(-1)
                            .foregroundStyle(Ink.black)
                        Text("Your Google Tasks, right next to the timer. Pick one to use as the intention for your next block.")
                            .font(TypeStyle.body(14))
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    if service.isConnected {
                        Button {
                            Task { await service.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BrutalButtonStyle(fill: Ink.white))
                        .disabled(service.isBusy)
                    }
                }

                if let error = service.errorMessage {
                    Text(error)
                        .font(TypeStyle.body(13))
                        .foregroundStyle(Ink.black)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brutalCard(Ink.coral, shadow: 4)
                }

                if service.isConnected {
                    connectedContent
                } else {
                    setupCard
                }
            }
            .padding(32)
        }
        .task {
            if service.isConnected && service.lists.isEmpty { await service.refresh() }
        }
    }

    // MARK: Connected

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                SectionTitle(text: "List")
                Picker("", selection: Binding(
                    get: { settings.googleTaskListID },
                    set: { id in Task { await service.selectList(id) } }
                )) {
                    ForEach(service.lists) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 240)
                if service.isBusy { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 10) {
                TextField("Add a task…", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(TypeStyle.body(15))
                    .foregroundStyle(Ink.black)
                    .padding(12)
                    .background(Ink.white)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
                    .onSubmit { submitNewTask() }
                Button("Add") { submitNewTask() }
                    .buttonStyle(BrutalButtonStyle(fill: Ink.yellow, size: 12, horizontalPadding: 16, verticalPadding: 11))
                    .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if service.tasks.isEmpty && !service.isBusy {
                Text("Inbox zero. Nothing open in this list.")
                    .font(TypeStyle.body(14))
                    .foregroundStyle(Ink.muted)
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .brutalCard(Ink.white)
            }

            ForEach(service.tasks) { task in
                TaskRow(task: task,
                        onComplete: { Task { await service.complete(task) } },
                        onFocus: {
                            engine.intention = task.title
                            NotificationCenter.default.post(name: .lockInShowScreen, object: Screen.focus.rawValue)
                        })
            }

            Button("Disconnect Google Tasks") { service.disconnect() }
                .buttonStyle(BrutalButtonStyle(fill: Ink.white, size: 11, horizontalPadding: 14, verticalPadding: 9))
                .padding(.top, 8)
        }
    }

    private func submitNewTask() {
        let title = newTask
        newTask = ""
        Task { await service.add(title: title) }
    }

    // MARK: Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(text: "Connect Google Tasks")
            Text("LockIn talks to Google directly from your Mac, so it needs an OAuth client of your own. Takes about three minutes, once.")
                .font(TypeStyle.body(14))
                .foregroundStyle(Ink.black)

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Open the Google Cloud Console, create a project (any name), and enable the **Google Tasks API**.")
                step(2, "Under *APIs & Services → OAuth consent screen*, pick **External**, add yourself as a test user.")
                step(3, "Under *Credentials*, create an **OAuth client ID** of type **Desktop app**. Copy the client ID and client secret.")
                step(4, "Paste both into **Settings → Google Tasks**, then come back here and hit Connect. Your browser opens, you approve, done.")
            }

            HStack(spacing: 12) {
                Button {
                    Task { await service.connect() }
                } label: {
                    Label(service.isBusy ? "Waiting for Google…" : "Connect", systemImage: "link")
                }
                .buttonStyle(BrutalButtonStyle(fill: Ink.coral))
                .disabled(service.isBusy || settings.googleClientID.isEmpty)

                Button("Open Settings") {
                    NotificationCenter.default.post(name: .lockInShowScreen, object: Screen.settings.rawValue)
                }
                .buttonStyle(BrutalButtonStyle(fill: Ink.white))

                Link(destination: URL(string: "https://console.cloud.google.com/apis/credentials")!) {
                    Text("Google Cloud Console ↗")
                        .font(TypeStyle.label(12))
                        .foregroundStyle(Ink.black)
                        .underline()
                }
            }

            if settings.googleClientID.isEmpty {
                Text("Add a client ID in Settings to enable Connect.")
                    .font(TypeStyle.label(11))
                    .tracking(0.5)
                    .foregroundStyle(Ink.muted)
            }
        }
        .padding(22)
        .brutalCard(Ink.white)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(TypeStyle.label(12))
                .foregroundStyle(Ink.black)
                .frame(width: 26, height: 26)
                .background(Ink.yellow)
                .overlay(Rectangle().stroke(Ink.black, lineWidth: 2.5))
            Text(LocalizedStringKey(text))
                .font(TypeStyle.body(13))
                .foregroundStyle(Ink.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TaskRow: View {
    let task: GTask
    let onComplete: () -> Void
    let onFocus: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onComplete) {
                Rectangle()
                    .fill(Ink.white)
                    .frame(width: 24, height: 24)
                    .overlay(Rectangle().stroke(Ink.black, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(TypeStyle.body(15))
                    .foregroundStyle(Ink.black)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(TypeStyle.body(12))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let due = task.dueDate {
                Tag(text: due.formatted(.dateTime.month(.abbreviated).day()),
                    fill: due < Calendar.current.startOfDay(for: Date()) ? Ink.coral : Ink.white)
            }

            Button(action: onFocus) {
                Label("Focus on it", systemImage: "lock.fill")
            }
            .buttonStyle(BrutalButtonStyle(fill: Ink.yellow, size: 11, horizontalPadding: 12, verticalPadding: 8))
        }
        .padding(14)
        .brutalCard(Ink.white, shadow: 4)
    }
}
