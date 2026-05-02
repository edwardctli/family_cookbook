import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct CookLogDetailView: View {
    let recipeTitle: String
    let log: CookLog

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipeTitle)
                        .font(.title2.bold())
                    Text("\(log.cookName) cooked this on \(log.cookedOn.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                    Label("\(log.rating)/5", systemImage: "star.fill")
                        .foregroundStyle(.orange)
                    Text(log.mood)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, 8)
            }

            Section("What Changed") {
                Text(log.tweakSummary)
            }

            Section("Notes") {
                Text(log.notes)
                Text("Next time: \(log.nextTimeNote)")
                    .foregroundStyle(.orange)
            }

            Section("Photo Timeline") {
                if log.photos.isEmpty {
                    Text("No photos attached.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.photos) { photo in
                        HStack(alignment: .top, spacing: 12) {
                            CookPhotoThumbnail(photo: photo)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(photo.stage)
                                    .font(.headline)
                                Text(photo.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Step Observations") {
                if log.observations.isEmpty {
                    Text("No step observations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.observations) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(observation.stepTitle)
                                .font(.headline)
                            Text(observation.note)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Cook Log")
    }
}

private struct CookPhotoThumbnail: View {
    let photo: CookPhoto

    var body: some View {
        Group {
            if let image = PlatformImage(data: photo.imageData), !photo.imageData.isEmpty {
                cookbookImage(from: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.orange.opacity(0.12))
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cookbookImage(from image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}

#Preview {
    NavigationStack {
        CookLogDetailView(recipeTitle: FamilyCookbookData.sampleRecipes[0].title, log: FamilyCookbookData.sampleRecipes[0].logs[0])
    }
    .modelContainer(FamilyCookbookPreview.container)
}

struct CDCookLogDetailView: View {
    let recipeTitle: String
    let log: CDCookLog

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipeTitle)
                        .font(.title2.bold())
                    Text("\(log.cookName) cooked this on \(log.cookedOn.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                    Label("\(log.rating)/5", systemImage: "star.fill")
                        .foregroundStyle(.orange)

                    if !log.mood.isEmpty {
                        Text(log.mood)
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(.vertical, 8)
            }

            if !log.tweakSummary.isEmpty {
                Section("What Changed") {
                    Text(log.tweakSummary)
                }
            }

            Section("Notes") {
                if !log.notes.isEmpty {
                    Text(log.notes)
                }

                if !log.nextTimeNote.isEmpty {
                    Text("Next time: \(log.nextTimeNote)")
                        .foregroundStyle(.orange)
                }
            }

            Section("Photo Timeline") {
                if log.sortedPhotos.isEmpty {
                    Text("No photos attached.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.sortedPhotos, id: \.objectID) { photo in
                        HStack(alignment: .top, spacing: 12) {
                            CDCookPhotoThumbnail(photo: photo)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(photo.stage)
                                    .font(.headline)
                                Text(photo.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Step Observations") {
                if log.sortedObservations.isEmpty {
                    Text("No step observations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.sortedObservations, id: \.objectID) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(observation.stepTitle)
                                .font(.headline)
                            Text(observation.note)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Cook Log")
    }
}

private struct CDCookPhotoThumbnail: View {
    let photo: CDCookPhoto

    var body: some View {
        Group {
            if let data = photo.imageData,
               !data.isEmpty,
               let image = PlatformImage(data: data) {
                cookbookImage(from: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.orange.opacity(0.12))
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cookbookImage(from image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}
