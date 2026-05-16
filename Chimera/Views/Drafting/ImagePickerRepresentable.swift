// ImagePickerRepresentable.swift
// Chimera Law
// PHPickerViewController wrapper for photo library selection

import SwiftUI
import PhotosUI

struct ImagePickerRepresentable: UIViewControllerRepresentable {

    var onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {

        let parent: ImagePickerRepresentable

        init(_ parent: ImagePickerRepresentable) {
            self.parent = parent
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            defer { parent.dismiss() }

            guard let result = results.first else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                if let error {
                    Logger.app.error("Image loading error: \(error.localizedDescription)")
                    return
                }
                guard let uiImage = image as? UIImage else { return }
                DispatchQueue.main.async {
                    self.parent.onImageSelected(uiImage)
                }
            }
        }
    }
}

// MARK: - Camera Picker (UIImagePickerController in .camera mode)

struct CameraPickerRepresentable: UIViewControllerRepresentable {

    var onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        let parent: CameraPickerRepresentable

        init(_ parent: CameraPickerRepresentable) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Shared Logger

import os

extension Logger {
    static let app = Logger(subsystem: "com.daimos.chimera", category: "General")
}
