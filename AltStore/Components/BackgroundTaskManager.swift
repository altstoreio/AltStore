//
//  BackgroundTaskManager.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import AVFoundation

final class BackgroundTaskManager
{
    static let shared = BackgroundTaskManager()
    
    private var isPlaying = false
    
    private let audioEngine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let audioFile: AVAudioFile
    
    private let audioEngineQueue: DispatchQueue
    
    private init()
    {
        self.audioEngine = AVAudioEngine()
        self.audioEngine.mainMixerNode.outputVolume = 0.0
        
        self.player = AVAudioPlayerNode()
        self.audioEngine.attach(self.player)
        
        do
        {
            let audioFileURL = Bundle.main.url(forResource: "Silence", withExtension: "m4a")!
            
            self.audioFile = try AVAudioFile(forReading: audioFileURL)
            self.audioEngine.connect(self.player, to: self.audioEngine.mainMixerNode, format: self.audioFile.processingFormat)
        }
        catch
        {
            fatalError("Error. \(error)")
        }
        
        self.audioEngineQueue = DispatchQueue(label: "com.altstore.BackgroundTaskManager")
    }
}

extension BackgroundTaskManager
{
    func performExtendedBackgroundTask(taskHandler: @escaping ((Result<Void, Error>, @escaping () -> Void) -> Void))
    {
        func finish()
        {
            self.player.stop()
            self.audioEngine.stop()
            
            self.isPlaying = false
        }
        
        self.audioEngineQueue.sync {
            do
            {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true)
                
                // Schedule audio file buffers.
                self.scheduleAudioFile()
                self.scheduleAudioFile()
                
                let outputFormat = self.audioEngine.outputNode.outputFormat(forBus: 0)
                self.audioEngine.connect(self.audioEngine.mainMixerNode, to: self.audioEngine.outputNode, format: outputFormat)
                
                try self.audioEngine.start()
                self.player.play()
                
                self.isPlaying = true
                
                taskHandler(.success(())) {
                    finish()
                }
            }
            catch
            {
                taskHandler(.failure(error)) {
                    finish()
                }
            }
        }
    }
}

private extension BackgroundTaskManager
{
    func scheduleAudioFile()
    {
        self.player.scheduleFile(self.audioFile, at: nil) {
            self.audioEngineQueue.async {
                guard self.isPlaying else { return }
                self.scheduleAudioFile()
            }
        }
    }
}
