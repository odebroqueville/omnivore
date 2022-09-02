//
//  AudioSession.swift
//
//
//  Created by Jackson Harper on 8/15/22.
//

import AVFoundation
import CryptoKit
import Foundation
import MediaPlayer
import Models
import Utils

public enum AudioSessionState {
  case stopped
  case paused
  case loading
  case playing
}

public enum PlayerScrubState {
  case reset
  case scrubStarted
  case scrubEnded(TimeInterval)
}

enum DownloadType: String {
  case mp3
  case speechMarks
}

enum DownloadPriority: String {
  case low
  case high
}

// Our observable object class
public class AudioSession: NSObject, ObservableObject, AVAudioPlayerDelegate, CachingPlayerItemDelegate {
  @Published public var state: AudioSessionState = .stopped
  @Published public var item: LinkedItem?

  @Published public var timeElapsed: TimeInterval = 0
  @Published public var duration: TimeInterval = 0
  @Published public var timeElapsedString: String?
  @Published public var durationString: String?

  let appEnvironment: AppEnvironment
  let networker: Networker

  var timer: Timer?
  var player: AVPlayer?
  var downloadTask: Task<Void, Error>?

  public init(appEnvironment: AppEnvironment, networker: Networker) {
    self.appEnvironment = appEnvironment
    self.networker = networker
  }

  public func play(item: LinkedItem) {
    stop()

    self.item = item
    startAudio()
  }

  public func stop() {
    // player?.stop()
    clearNowPlayingInfo()
    timer = nil
    player = nil
    item = nil
    state = .stopped
    timeElapsed = 0
    duration = 1
    downloadTask?.cancel()
  }

  public func preload(itemIDs: [String], retryCount: Int = 0) async -> Bool {
    var pendingList = [String]()

    for pageId in itemIDs {
      let permFile = pathForAudioFile(pageId: pageId)
      if FileManager.default.fileExists(atPath: permFile.path) {
        print("audio file already downloaded: ", permFile)
        continue
      }

      // Attempt to fetch the file if not downloaded already
      let result = try? await downloadAudioFile(pageId: pageId, type: .mp3, priority: .low)
      if result == nil {
        print("audio file had error downloading: ", pageId)
        pendingList.append(pageId)
      }

      if let result = result, result.pending {
        print("audio file is pending download: ", pageId)
        pendingList.append(pageId)
      } else {
        print("audio file is downloaded: ", pageId)
      }
    }

    print("audio files pending download: ", pendingList)
    if pendingList.isEmpty {
      return true
    }

    if retryCount > 5 {
      print("reached max preload depth, stopping preloading")
      return false
    }

    let retryDelayInNanoSeconds = UInt64(retryCount * 2 * 1_000_000_000)
    try? await Task.sleep(nanoseconds: retryDelayInNanoSeconds)

    return await preload(itemIDs: pendingList, retryCount: retryCount + 1)
  }

  public var localAudioUrl: URL? {
    if let pageId = item?.id {
      return FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(pageId + ".mp3")
    }
    return nil
  }

  public var scrubState: PlayerScrubState = .reset {
    didSet {
      switch scrubState {
      case .reset:
        return
      case .scrubStarted:
        return
      case let .scrubEnded(seekTime):
        seek(to: seekTime)
//        player?.currentTime = seekTime
      }
    }
  }

  public func seek(to _: TimeInterval) {
    // seek
  }

  public var currentVoice: String {
    "en-US-JennyNeural"
  }

  public func isLoadingItem(item: LinkedItem) -> Bool {
    state == .loading && self.item == item
  }

  public func isPlayingItem(item: LinkedItem) -> Bool {
    state == .playing && self.item == item
  }

  public func skipForward(seconds _: Double) {
//    if let current = player?.currentTime {
//      seek(to: current + seconds)
    ////      player?.currentTime = min(duration, current + seconds)
//    }
  }

  public func skipBackwards(seconds _: Double) {
//    if let current = player?.currentTime {
//      seek(to: current + seconds)
//
    ////      player?.currentTime = max(0, current - seconds)
//    }
  }

  public func fileNameForAudioFile(_ pageId: String) -> String {
    pageId + "-" + currentVoice + ".mp3"
  }

  public func pathForAudioFile(pageId: String) -> URL {
    FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(fileNameForAudioFile(pageId))
  }

  public func startAudio() {
    state = .loading
    setupNotifications()

    let pageId = item!.unwrappedID

    downloadTask = Task {
//      let result = try? await downloadAudioFile(pageId: pageId, type: .mp3, priority: .high)
//      if Task.isCancelled { return }
//
//      if result == nil {
//        DispatchQueue.main.async {
//          NSNotification.operationSuccess(message: "Error generating audio.")
//          self.stop()
//        }
//      }
//
//      if let result = result, result.pending {
//        DispatchQueue.main.async {
//          NSNotification.operationSuccess(message: "Your audio is being generated.")
//        }
//      }

      DispatchQueue.main.async {
        self.startDownloadedAudioFile(pageId: pageId)
      }
    }
  }

  private func startDownloadedAudioFile(pageId: String) {
    // Make sure audio file is still correct for the current page
    guard item?.unwrappedID == pageId else {
      state = .stopped
      return
    }
//
//    // TODO: Maybe check if app is active so it doesn't end up playing later?
//
//    let audioUrl = pathForAudioFile(pageId: pageId)
//    if !FileManager.default.fileExists(atPath: audioUrl.path) {
//      stop()
//      return
//    }

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])

      let token = ValetKey.authToken.value()!
      let url = URL(string: "https://text-to-speech-streaming-bryle2uxwq-wl.a.run.app/audio.mp3?token=\(token)&q=1")!
      print("LOADING URL: ", url.absoluteURL)

      //   let url = URL(string: "https://storage.googleapis.com/omnivore-demo-files/speech/062bfcc2-8d59-4880-8a67-fe6ee739c510.mp3")!
//      let url = URL(string: "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8")!
      let urlRequest = URLRequest(url: url)
//      urlRequest.httpMethod = "POST"
//      urlRequest.httpBody

      let playerItem = CachingPlayerItem(urlRequest: urlRequest)
      playerItem.delegate = self

      player = AVPlayer(playerItem: playerItem)
      print("created player: ", player, player?.error)
      player?.automaticallyWaitsToMinimizeStalling = false

      player?.play()
      print("starting playing: ", player, player?.error)

//
//      player = try AVAudioPlayer(contentsOf: audioUrl)
//      player?.delegate = self
//      if player?.play() ?? false {
      state = .playing
      startTimer()
      //      setupRemoteControl()
      //   }
    } catch {
      print("error playing MP3 file", error)
      // try? FileManager.default.removeItem(atPath: audioUrl.path)
      state = .stopped
    }
  }

  public func pause() -> Bool {
    if let player = player {
      player.pause()
      state = .paused
      return true
    }
    return false
  }

  public func unpause() -> Bool {
    playAudio()
  }

  public func playAudio() -> Bool {
    if let player = player {
      player.play()
      state = .playing
      return true
    }
    return false
  }

  func startTimer() {
    if timer == nil {
      // Update every 100ms
      timer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(update(_:)), userInfo: nil, repeats: true)
      timer?.fire()
    }
  }

  func stopTimer() {
    timer = nil
  }

  func formatTimeInterval(_ time: TimeInterval) -> String? {
    let componentFormatter = DateComponentsFormatter()
    componentFormatter.unitsStyle = .positional
    componentFormatter.allowedUnits = time >= 3600 ? [.second, .minute, .hour] : [.second, .minute]
    componentFormatter.zeroFormattingBehavior = .pad
    return componentFormatter.string(from: time)
  }

  // Every second, get the current playing time of the player and refresh the status of the player progressslider
  @objc func update(_: Timer) {
    if let player = player {
      print("current error: ", player.error)
      print("current state", player.rate)
      print("current position", player.currentTime())
      print("timeControlStatus", player.timeControlStatus.rawValue)
      print("waiting Reason: ", player.reasonForWaitingToPlay?.rawValue)
      print("currentItem.duration: ", player.currentItem?.duration)
      print("status:", player.currentItem?.status.rawValue)
      print("error:", player.currentItem?.error)
      print("error log:", player.currentItem?.errorLog())
    }
//    if let player = player, player.isPlaying {
//      duration = player.duration
//      durationString = formatTimeInterval(duration)
//
//      switch scrubState {
//      case .reset:
//        timeElapsed = player.currentTime
//        timeElapsedString = formatTimeInterval(timeElapsed)
//        if var nowPlaying = MPNowPlayingInfoCenter.default().nowPlayingInfo {
//          nowPlaying[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
//          nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: timeElapsed)
//          MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
//        }
//      case .scrubStarted:
//        break
//      case let .scrubEnded(seekTime):
//        scrubState = .reset
//        timeElapsed = seekTime
//      }
//    }
  }

  func clearNowPlayingInfo() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
  }

  func setupRemoteControl() {
    UIApplication.shared.beginReceivingRemoteControlEvents()

    if let item = item {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = [
        MPMediaItemPropertyTitle: NSString(string: item.title ?? "Your Omnivore Article"),
        MPMediaItemPropertyArtist: NSString(string: item.author ?? "Omnivore"),
        MPMediaItemPropertyPlaybackDuration: NSNumber(value: duration),
        MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: timeElapsed)
      ]
    }

    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { _ -> MPRemoteCommandHandlerStatus in
      self.unpause()
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { _ -> MPRemoteCommandHandlerStatus in
      self.pause()
      return .success
    }

    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [30, 60]
    commandCenter.skipForwardCommand.addTarget { event -> MPRemoteCommandHandlerStatus in
      if let event = event as? MPSkipIntervalCommandEvent {
        self.skipForward(seconds: event.interval)
        return .success
      }
      return .commandFailed
    }

    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [30, 60]
    commandCenter.skipBackwardCommand.addTarget { event -> MPRemoteCommandHandlerStatus in
      if let event = event as? MPSkipIntervalCommandEvent {
        self.skipBackwards(seconds: event.interval)
        return .success
      }
      return .commandFailed
    }

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { event -> MPRemoteCommandHandlerStatus in
      if let event = event as? MPChangePlaybackPositionCommandEvent {
        self.seek(to: event.positionTime)
//        self.player?.currentTime = event.positionTime
        return .success
      }
      return .commandFailed
    }
  }

  func downloadAudioFile(pageId: String, type: DownloadType, priority: DownloadPriority) async throws -> (pending: Bool, url: URL?) {
    let audioUrl = pathForAudioFile(pageId: pageId)

    if FileManager.default.fileExists(atPath: audioUrl.path) {
      return (pending: false, url: audioUrl)
    }

    let path = "/api/article/\(pageId)/\(type)/\(priority)/\(currentVoice)"
    guard let url = URL(string: path, relativeTo: appEnvironment.serverBaseURL) else {
      throw BasicError.message(messageText: "Invalid audio URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 600
    for (header, value) in networker.defaultHeaders {
      request.setValue(value, forHTTPHeaderField: header)
    }

    let result: (Data, URLResponse)? = try? await URLSession.shared.data(for: request)
    guard let httpResponse = result?.1 as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
      throw BasicError.message(messageText: "audioFetch failed. no response or bad status code.")
    }

    if let httpResponse = result?.1 as? HTTPURLResponse, httpResponse.statusCode == 202 {
      return (pending: true, nil)
    }

    guard let data = result?.0 else {
      throw BasicError.message(messageText: "audioFetch failed. no data received.")
    }

    let tempPath = FileManager.default
      .urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(UUID().uuidString + ".mp3")

    do {
      if let googleHash = httpResponse.value(forHTTPHeaderField: "x-goog-hash") {
        let hash = Data(Insecure.MD5.hash(data: data)).base64EncodedString()
        if !googleHash.contains("md5=\(hash)") {
          print("Downloaded mp3 file hashes do not match: returned: \(googleHash) v computed: \(hash)")
          throw BasicError.message(messageText: "Downloaded mp3 file hashes do not match: returned: \(googleHash) v computed: \(hash)")
        }
      }

      try data.write(to: tempPath)
      try? FileManager.default.removeItem(at: audioUrl)
      try FileManager.default.moveItem(at: tempPath, to: audioUrl)
    } catch {
      print("error writing file: ", error)
      let errorMessage = "audioFetch failed. could not write MP3 data to disk"
      throw BasicError.message(messageText: errorMessage)
    }

    return (pending: false, url: audioUrl)
  }

  public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
    if player == self.player {
      pause()
      player.currentTime = 0
    }
  }

  func setupNotifications() {
    NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleInterruption),
                                           name: AVAudioSession.interruptionNotification,
                                           object: AVAudioSession.sharedInstance())
  }

  @objc func handleInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      return
    }

    // Switch over the interruption type.
    switch type {
    case .began:
      // An interruption began. Update the UI as necessary.
      pause()
    case .ended:
      // An interruption ended. Resume playback, if appropriate.

      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        unpause()
      } else {}
    default: ()
    }
  }

  /// Is called when the media file is fully downloaded.
  @objc func playerItem(_: CachingPlayerItem, didFinishDownloadingData data: Data) {
    print("didFinishDownloadingData: ", data.underestimatedCount)
  }

  /// Is called every time a new portion of data is received.
  @objc func playerItem(_: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf _: Int) {
    print("didDownloadBytesSoFar: ", bytesDownloaded)
  }

  /// Is called after initial prebuffering is finished, means
  /// we are ready to play.
  @objc func playerItemReadyToPlay(_: CachingPlayerItem) {
    print("playerItemReadyToPlay")
    player?.play()
  }

  /// Is called when the data being downloaded did not arrive in time to
  /// continue playback.
  @objc func playerItemPlaybackStalled(_: CachingPlayerItem) {
    print("playerItemPlaybackStalled")
  }

  /// Is called on downloading error.
  @objc func playerItem(_: CachingPlayerItem, downloadingFailedWith error: Error) {
    print("downloadingFailedWith errpr", error)
  }
}
