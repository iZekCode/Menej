//
//  CameraPicker.swift
//  Menej
//
//  SwiftUI has no native camera-capture view, so we wrap
//  `UIImagePickerController`'s camera source. Returns the captured photo as
//  JPEG data. Only present this when `isAvailable` is true — the camera
//  source is unavailable on Simulator and on devices without a camera.
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// Bound to the presenter so the coordinator can dismiss on capture/cancel.
    @Binding var isPresented: Bool
    /// Called with JPEG data when the user keeps a photo.
    var onCapture: (Data) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
