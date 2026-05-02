import PhotosUI
import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct NewCookLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let recipe: Recipe

    @State private var cookName = ""
    @State private var rating = 4.0
    @State private var mood = ""
    @State private var tweakSummary = ""
    @State private var notes = ""
    @State private var nextTimeNote = ""
    @State private var photoEntries: [DraftCookPhoto] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var stepObservations: [DraftStepObservation]
    @State private var photoLoadError: String?
    @State private var cameraError: String?
    @State private var showingPhotoSourceOptions = false
    @State private var showingCameraCapture = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _stepObservations = State(initialValue: recipe.steps.map { DraftStepObservation(stepTitle: $0.title) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("This Cook") {
                    TextField("Who cooked?", text: $cookName)
                    TextField("Mood or vibe", text: $mood)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rating: \(Int(rating))/5")
                        Slider(value: $rating, in: 1...5, step: 1)
                            .tint(.orange)
                    }
                }

                Section("Changes") {
                    TextField("What did you do differently?", text: $tweakSummary, axis: .vertical)
                        .lineLimit(3...5)
                    TextField("How did it turn out?", text: $notes, axis: .vertical)
                        .lineLimit(4...6)
                    TextField("What should happen next time?", text: $nextTimeNote, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("Photos") {
                    Button {
                        showingPhotoSourceOptions = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }

                    if let photoLoadError {
                        Text(photoLoadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let cameraError {
                        Text(cameraError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if photoEntries.isEmpty {
                        Text("Attach prep, in-progress, or plated photos for this cook.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($photoEntries) { $entry in
                            VStack(alignment: .leading, spacing: 12) {
                                if let image = PlatformImage(data: entry.imageData) {
                                    cookbookImage(from: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 180)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                TextField("Stage", text: $entry.stage)
                                TextField("Caption", text: $entry.caption, axis: .vertical)
                                    .lineLimit(2...4)

                                Button("Remove Photo", role: .destructive) {
                                    photoEntries.removeAll { $0.id == entry.id }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Step Notes") {
                    if stepObservations.isEmpty {
                        Text("This recipe has no saved steps yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($stepObservations) { $observation in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(observation.stepTitle)
                                    .font(.headline)
                                TextField("What did you notice on this step?", text: $observation.note, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("New Cook Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveLog()
                    }
                    .disabled(tweakSummary.isEmpty && notes.isEmpty)
                }
            }
            .task(id: selectedPhotoItems) {
                await importSelectedPhotos()
            }
            .confirmationDialog("Add Photo", isPresented: $showingPhotoSourceOptions, titleVisibility: .visible) {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }

                #if canImport(UIKit)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        showingCameraCapture = true
                    }
                }
                #endif

                Button("Cancel", role: .cancel) {}
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showingCameraCapture) {
                CameraCaptureView { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        photoEntries.append(DraftCookPhoto(imageData: data))
                        cameraError = nil
                    } else {
                        cameraError = "The captured photo could not be saved."
                    }
                }
            }
            #endif
        }
    }

    private func saveLog() {
        let log = CookLog(
            cookedOn: .now,
            cookName: cookName.isEmpty ? "Unknown Cook" : cookName,
            rating: Int(rating),
            mood: mood,
            tweakSummary: tweakSummary,
            notes: notes,
            nextTimeNote: nextTimeNote,
            photos: photoEntries.map { entry in
                CookPhoto(stage: entry.stageText, caption: entry.captionText, imageData: entry.imageData)
            },
            observations: stepObservations
                .filter { !$0.noteText.isEmpty }
                .map { StepObservation(stepTitle: $0.stepTitle, note: $0.noteText) }
        )

        recipe.logs.insert(log, at: 0)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            photoLoadError = "Could not save this cook log. Try again."
        }
    }

    @MainActor
    private func importSelectedPhotos() async {
        guard !selectedPhotoItems.isEmpty else {
            return
        }

        let items = selectedPhotoItems
        selectedPhotoItems = []
        photoLoadError = nil

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                photoEntries.append(DraftCookPhoto(imageData: data))
            } catch {
                photoLoadError = "One or more photos could not be loaded."
            }
        }
    }

    private func cookbookImage(from image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}

#if canImport(UIKit)
private struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let dismiss: DismissAction
        private let onCapture: (UIImage) -> Void

        init(dismiss: DismissAction, onCapture: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onCapture = onCapture
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }
    }
}
#endif

private struct DraftCookPhoto: Identifiable {
    let id = UUID()
    var stage = ""
    var caption = ""
    var imageData: Data

    var stageText: String {
        stage.isEmpty ? "Photo" : stage
    }

    var captionText: String {
        caption.isEmpty ? "Cook photo" : caption
    }
}

private struct DraftStepObservation: Identifiable {
    let id = UUID()
    let stepTitle: String
    var note = ""

    var noteText: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NewCookLogView(recipe: FamilyCookbookData.sampleRecipes[0])
        .modelContainer(FamilyCookbookPreview.container)
}

struct CDNewCookLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext

    let recipe: CDRecipe

    @State private var cookName = ""
    @State private var rating = 4.0
    @State private var mood = ""
    @State private var tweakSummary = ""
    @State private var notes = ""
    @State private var nextTimeNote = ""
    @State private var photoEntries: [CDDraftCookPhoto] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var stepObservations: [CDDraftStepObservation]
    @State private var photoLoadError: String?
    @State private var cameraError: String?
    @State private var showingPhotoSourceOptions = false
    @State private var showingCameraCapture = false

    init(recipe: CDRecipe) {
        self.recipe = recipe
        _stepObservations = State(initialValue: recipe.sortedSteps.map { CDDraftStepObservation(stepTitle: $0.title) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("This Cook") {
                    TextField("Who cooked?", text: $cookName)
                    TextField("Mood or vibe", text: $mood)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rating: \(Int(rating))/5")
                        Slider(value: $rating, in: 1...5, step: 1)
                            .tint(.orange)
                    }
                }

                Section("Changes") {
                    TextField("What did you do differently?", text: $tweakSummary, axis: .vertical)
                        .lineLimit(3...5)
                    TextField("How did it turn out?", text: $notes, axis: .vertical)
                        .lineLimit(4...6)
                    TextField("What should happen next time?", text: $nextTimeNote, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("Photos") {
                    Button {
                        showingPhotoSourceOptions = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }

                    if let photoLoadError {
                        Text(photoLoadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let cameraError {
                        Text(cameraError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if photoEntries.isEmpty {
                        Text("Attach prep, in-progress, or plated photos for this cook.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($photoEntries) { $entry in
                            VStack(alignment: .leading, spacing: 12) {
                                if let image = PlatformImage(data: entry.imageData) {
                                    cookbookImage(from: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 180)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                TextField("Stage", text: $entry.stage)
                                TextField("Caption", text: $entry.caption, axis: .vertical)
                                    .lineLimit(2...4)

                                Button("Remove Photo", role: .destructive) {
                                    photoEntries.removeAll { $0.id == entry.id }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Step Notes") {
                    if stepObservations.isEmpty {
                        Text("This recipe has no saved steps yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($stepObservations) { $observation in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(observation.stepTitle)
                                    .font(.headline)
                                TextField("What did you notice on this step?", text: $observation.note, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("New Cook Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveLog()
                    }
                    .disabled(tweakSummary.isEmpty && notes.isEmpty)
                }
            }
            .task(id: selectedPhotoItems) {
                await importSelectedPhotos()
            }
            .confirmationDialog("Add Photo", isPresented: $showingPhotoSourceOptions, titleVisibility: .visible) {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }

                #if canImport(UIKit)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        showingCameraCapture = true
                    }
                }
                #endif

                Button("Cancel", role: .cancel) {}
            }
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $showingCameraCapture) {
                CameraCaptureView { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        photoEntries.append(CDDraftCookPhoto(imageData: data))
                        cameraError = nil
                    } else {
                        cameraError = "The captured photo could not be saved."
                    }
                }
            }
            #endif
        }
    }

    private func saveLog() {
        let log = CDCookLog(context: managedObjectContext)
        log.id = UUID()
        log.cookedOn = .now
        log.cookName = cookName.isEmpty ? "Unknown Cook" : cookName
        log.rating = Int16(Int(rating))
        log.mood = mood
        log.tweakSummary = tweakSummary
        log.notes = notes
        log.nextTimeNote = nextTimeNote
        log.createdAt = .now
        log.updatedAt = .now
        log.recipe = recipe

        for (index, entry) in photoEntries.enumerated() {
            let photo = CDCookPhoto(context: managedObjectContext)
            photo.id = UUID()
            photo.stage = entry.stageText
            photo.caption = entry.captionText
            photo.imageData = entry.imageData
            photo.sortOrder = Int32(index)
            photo.log = log
        }

        for (index, observation) in stepObservations.enumerated() where !observation.noteText.isEmpty {
            let item = CDStepObservation(context: managedObjectContext)
            item.id = UUID()
            item.stepTitle = observation.stepTitle
            item.note = observation.noteText
            item.sortOrder = Int32(index)
            item.log = log
        }

        recipe.updatedAt = log.cookedOn

        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            photoLoadError = "Could not save this cook log. Try again."
        }
    }

    @MainActor
    private func importSelectedPhotos() async {
        guard !selectedPhotoItems.isEmpty else {
            return
        }

        let items = selectedPhotoItems
        selectedPhotoItems = []
        photoLoadError = nil

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                photoEntries.append(CDDraftCookPhoto(imageData: data))
            } catch {
                photoLoadError = "One or more photos could not be loaded."
            }
        }
    }

    private func cookbookImage(from image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}

private struct CDDraftCookPhoto: Identifiable {
    let id = UUID()
    var stage = ""
    var caption = ""
    var imageData: Data

    var stageText: String {
        stage.isEmpty ? "Photo" : stage
    }

    var captionText: String {
        caption.isEmpty ? "Cook photo" : caption
    }
}

private struct CDDraftStepObservation: Identifiable {
    let id = UUID()
    let stepTitle: String
    var note = ""

    var noteText: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
