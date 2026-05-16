// SpeechRecognitionService.swift
// Chimera Law
// On-device speech-to-text using SFSpeechRecognizer + AVAudioEngine

import Foundation
import Speech
import AVFoundation
import Combine
import os

@MainActor
final class SpeechRecognitionService: ObservableObject {

    // MARK: - Published State

    var isRecording: Bool = false {
        willSet { objectWillChange.send() }
    }

    var transcript: String = "" {
        willSet { objectWillChange.send() }
    }

    var errorMessage: String? {
        willSet { objectWillChange.send() }
    }

    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined {
        willSet { objectWillChange.send() }
    }

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let logger = Logger(subsystem: "com.daimos.chimera", category: "Speech")

    // MARK: - Init

    init(locale: Locale = Locale(identifier: "en-GB")) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        // Seed the published status from the current system value so the
        // microphone button renders correctly on first appearance without
        // having to wait for a requestAuthorization round-trip.
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Authorization

    /// Re-reads the system authorisation status without prompting the user.
    /// Call when the app returns to the foreground so the button state
    /// reflects any permission change the user made in Settings.
    func refreshAuthorizationStatus() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                if status != .authorized {
                    self?.errorMessage = "Speech recognition not authorized."
                }
            }
        }
    }

    var isAvailable: Bool {
        authorizationStatus == .authorized && (speechRecognizer?.isAvailable ?? false)
    }

    // MARK: - Start / Stop

    /// Begins live transcription. Call `stopRecording()` to end.
    func startRecording() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }

        guard authorizationStatus == .authorized else {
            requestAuthorization()
            return
        }

        // Cancel any in-flight task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            logger.error("Audio session error: \(error.localizedDescription)")
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        // Install tap on audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
        }

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(
            with: recognitionRequest
        ) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    // Code 1 = "no speech detected", not a real error in many cases
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1 {
                        // Silently ignore
                    } else {
                        self.logger.error("Recognition error: \(error.localizedDescription)")
                    }
                    self.stopRecording()
                }

                if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }

        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            errorMessage = nil
            transcript = ""
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            logger.error("Audio engine error: \(error.localizedDescription)")
            stopRecording()
        }
    }

    /// Stops live transcription and cleans up resources.
    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Toggle: starts if not recording, stops if recording.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
}
