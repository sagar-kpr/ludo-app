(() => {
  if (window.__rallyMedia) return;
  let room, sdk, sdkPromise, epoch = 0, publishingEpoch = 0, wanted = false;
  let desiredCamera = false, desiredMicrophone = false, mediaQueue = Promise.resolve();
  const mutedParticipants = new Set();
  let layout = { visible: false, entries: [], width: 420, height: 860 };
  const events = [], videos = new Map(), audio = new Map();
  const emit = (state, message) => events.push({ state, message });
  function remoteAudioState() {
    const identities = new Set([...audio.values()].filter(entry => !entry.senderMuted).map(entry => entry.identity));
    emit('remote_audio_state',JSON.stringify([...identities]));
  }
  const mediaError = error => {
    if (['NotAllowedError','PermissionDeniedError','SecurityError'].includes(error?.name)) return 'Access was denied. Allow the camera or microphone you want to use in your browser settings, then try again.';
    if (['NotFoundError','DevicesNotFoundError'].includes(error?.name)) return 'No camera or microphone was found on this device.';
    if (error?.name === 'NotReadableError') return 'Your camera or microphone is being used by another app.';
    return 'Camera and voice could not connect. Check your connection and try again.';
  };
  function layer() {
    let target = document.querySelector('#rally-media-layer');
    if (target) return target;
    const stage = document.querySelector('#rally-stage');
    if (!stage) return null;
    target = document.createElement('div');
    target.id = 'rally-media-layer';
    target.style.cssText = 'position:absolute;inset:0;z-index:10;pointer-events:none;overflow:hidden;';
    stage.append(target);
    new ResizeObserver(place).observe(stage);
    return target;
  }
  function place() {
    const target = layer();
    if (!target) return;
    const canvas = document.querySelector('#canvas');
    const sx = canvas.clientWidth / layout.width, sy = canvas.clientHeight / layout.height;
    for (const [identity, entry] of videos) {
      const slot = layout.entries.find(slot => slot.id === identity);
      entry.element.hidden = !layout.visible || !slot || entry.muted;
      if (!slot) continue;
      const [x,y,w,h] = slot.rect;
      Object.assign(entry.element.style, { left:`${x*sx}px`, top:`${y*sy}px`, width:`${w*sx}px`, height:`${h*sy}px`, borderRadius:`${12*Math.min(sx,sy)}px` });
    }
    const unlock = document.querySelector('#rally-enable-voice');
    if (unlock) unlock.hidden = !layout.visible || !room || room.canPlaybackAudio;
  }
  function attach(track, participant) {
    const identity = participant.identity;
    if (track.kind === 'video') {
      removeVideo(identity);
      const element = document.createElement('video');
      element.autoplay = true;
      element.playsInline = true;
      element.muted = true; // Video elements never duplicate the separate audio track.
      element.dataset.playerId = identity;
      element.style.cssText = 'position:absolute;object-fit:cover;border:0;pointer-events:none;background:#10243d;';
      if (participant === room.localParticipant) element.style.transform = 'scaleX(-1)';
      track.attach(element);
      videos.set(identity, { element, track, muted: track.isMuted });
      layer()?.append(element);
      element.play().catch(() => {});
      place();
    } else if (track.kind === 'audio' && participant !== room.localParticipant) {
      const key = track.sid;
      if (audio.has(key)) return;
      const element = track.attach();
      element.muted = mutedParticipants.has(identity);
      element.dataset.playerId = identity;
      element.style.display = 'none';
      layer()?.append(element);
      audio.set(key, { element, track, identity, senderMuted:track.isMuted });
      remoteAudioState();
    }
  }
  function removeVideo(identity) {
    const previous = videos.get(identity);
    if (!previous) return;
    previous.track.detach(previous.element);
    previous.element.remove();
    videos.delete(identity);
  }
  function detach(track, participant) {
    if (track.kind === 'video' && videos.get(participant.identity)?.track === track) removeVideo(participant.identity);
    const previous = audio.get(track.sid);
    if (previous) { track.detach(previous.element); previous.element.remove(); audio.delete(track.sid); remoteAudioState(); }
  }
  function loadSDK() {
    if (!sdkPromise) sdkPromise = new Promise((resolve,reject) => {
      const script = document.createElement('script');
      script.src = new URL('livekit-client.umd.js', document.baseURI).href;
      script.onload = () => resolve(window.LivekitClient);
      script.onerror = () => { script.remove(); sdkPromise = null; reject(new Error('SDK unavailable')); };
      document.head.append(script);
    });
    return sdkPromise;
  }
  function unlockAudio() {
    room?.startAudio().then(place).catch(() => {});
  }
  document.addEventListener('pointerdown', unlockAudio, { passive:true });
  function makeAudioUnlock() {
    if (document.querySelector('#rally-enable-voice')) return;
    const button = document.createElement('button');
    button.id = 'rally-enable-voice';
    button.textContent = 'Tap to hear players';
    button.style.cssText = 'position:absolute;bottom:12px;left:50%;transform:translateX(-50%);border:1px solid #69b7e8;border-radius:14px;background:#153350;color:white;padding:10px 16px;pointer-events:auto;font:14px Arial;';
    button.onclick = unlockAudio;
    layer()?.append(button);
  }
  function stopLocal(current) {
    if (!current) return;
    for (const publication of current.localParticipant.trackPublications.values()) {
      if (publication.track) {
        const track = publication.track;
        track.stop(); // Release camera and microphone immediately, even on a bad connection.
        current.localParticipant.unpublishTrack(track, true).catch(() => {});
      }
    }
    removeVideo(current.localParticipant.identity);
  }
  function disconnect(clearMutes = true) {
    epoch++; publishingEpoch++; wanted = false;
    desiredCamera = false; desiredMicrophone = false;
    mediaQueue = Promise.resolve();
    if (clearMutes) mutedParticipants.clear();
    const previous = room; room = null;
    if (previous) { stopLocal(previous); previous.disconnect().catch(() => {}); }
    for (const identity of [...videos.keys()]) removeVideo(identity);
    for (const entry of audio.values()) { entry.track.detach(entry.element); entry.element.remove(); }
    audio.clear();
    remoteAudioState();
    document.querySelector('#rally-enable-voice')?.remove();
  }
  async function connect(credentials) {
    disconnect(false);
    const attempt = epoch;
    try {
      sdk = await loadSDK();
      if (attempt !== epoch) return;
      const current = new sdk.Room({
        adaptiveStream:true, dynacast:true,
        videoCaptureDefaults:{ facingMode:'user', resolution:{...sdk.VideoPresets.h360.resolution,frameRate:15} },
        audioCaptureDefaults:{ echoCancellation:true, noiseSuppression:true, autoGainControl:true, channelCount:1, sampleRate:48000 },
        publishDefaults:{ simulcast:true, videoEncoding:{...sdk.VideoPresets.h360.encoding,maxFramerate:15}, audioPreset:sdk.AudioPresets.music, dtx:true, red:true },
      });
      room = current;
      current.on(sdk.RoomEvent.TrackSubscribed, (track,publication,participant) => { if (room === current) attach(track,participant); });
      current.on(sdk.RoomEvent.TrackUnsubscribed, (track,publication,participant) => { if (room === current) detach(track,participant); });
      current.on(sdk.RoomEvent.LocalTrackPublished, publication => { if (room === current && publication.track?.kind === 'video') attach(publication.track,current.localParticipant); });
      current.on(sdk.RoomEvent.LocalTrackUnpublished, publication => { if (room === current && publication.track) detach(publication.track,current.localParticipant); });
      for (const event of [sdk.RoomEvent.TrackMuted,sdk.RoomEvent.TrackUnmuted]) current.on(event,(publication,participant) => {
        if (room !== current) return;
        if (publication.kind === 'audio') {
          for (const entry of audio.values()) if (entry.identity === participant.identity && entry.track === publication.track) entry.senderMuted = publication.isMuted;
          remoteAudioState();
          return;
        }
        if (publication.kind !== 'video') return;
        const entry = videos.get(participant.identity);
        if (entry) { entry.muted = publication.isMuted; place(); }
      });
      current.on(sdk.RoomEvent.ParticipantDisconnected, participant => {
        if (room !== current) return;
        removeVideo(participant.identity);
        for (const entry of [...audio.values()]) if (entry.identity === participant.identity) detach(entry.track,participant);
      });
      current.on(sdk.RoomEvent.AudioPlaybackStatusChanged,place);
      current.on(sdk.RoomEvent.Reconnecting,() => { if (room === current) emit('reconnecting','Voice is reconnecting…'); });
      current.on(sdk.RoomEvent.Reconnected,() => { if (room === current) emit('connected','Voice connection restored.'); });
      current.on(sdk.RoomEvent.Disconnected,() => {
        if (room !== current) return;
        disconnect(); emit('disconnected','Voice disconnected. Tap the camera to reconnect.');
      });
      await current.connect(credentials.url,credentials.token,{autoSubscribe:true});
      if (attempt !== epoch) { await current.disconnect(); return; }
      makeAudioUnlock();
      unlockAudio();
      emit('connected','You can see and hear players. Your camera and microphone are off.');
      place();
    } catch (error) {
      if (attempt === epoch) { disconnect(); emit('error',mediaError(error)); }
    }
  }
  function setParticipantMuted(identity, muted) {
    if (muted) mutedParticipants.add(identity); else mutedParticipants.delete(identity);
    for (const entry of audio.values()) if (entry.identity === identity) entry.element.muted = muted;
  }
  function stopKind(current, kind) {
    if (!current) return;
    for (const publication of current.localParticipant.trackPublications.values()) {
      const track = publication.track;
      if (track?.kind !== kind) continue;
      track.stop();
      current.localParticipant.unpublishTrack(track,true).catch(()=>{});
    }
    if (kind === 'video') removeVideo(current.localParticipant.identity);
  }
  function localState(current) {
    const live = kind => [...current.localParticipant.trackPublications.values()].some(p => p.track?.kind === kind && p.track.mediaStreamTrack.readyState === 'live' && !p.isMuted);
    const camera = live('video'), microphone = live('audio');
    emit(camera ? 'camera_enabled' : 'camera_disabled',camera ? 'Camera on.' : 'Camera off.');
    emit(microphone ? 'microphone_enabled' : 'microphone_disabled',microphone ? 'Microphone on.' : 'Microphone off.');
    if (camera && microphone) emit('publishing_enabled','Camera and microphone on.');
    if (!camera && !microphone) emit('publishing_disabled','Camera and microphone off.');
  }
  function setLocalMedia(camera, microphone) {
    desiredCamera = !!camera; desiredMicrophone = !!microphone;
    wanted = desiredCamera || desiredMicrophone;
    const attempt = ++publishingEpoch, current = room;
    // Stop unwanted capture immediately, including while another request waits
    // for permission. Late captures are discarded by the generation checks.
    if (!desiredCamera) stopKind(current,'video');
    if (!desiredMicrophone) stopKind(current,'audio');
    if (current && current.state !== 'connected') localState(current);
    mediaQueue = mediaQueue.catch(()=>{}).then(async () => {
      if (attempt !== publishingEpoch || room !== current || current?.state !== 'connected') return;
      const has = kind => [...current.localParticipant.trackPublications.values()].some(p => p.track?.kind === kind && p.track.mediaStreamTrack.readyState === 'live');
      const needCamera = desiredCamera && !has('video'), needMicrophone = desiredMicrophone && !has('audio');
      for (const [kind, needed] of [['video',needCamera],['audio',needMicrophone]]) {
        if (!needed || attempt !== publishingEpoch || room !== current) continue;
        let tracks = [];
        try {
          if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw {name:'SecurityError'};
          emit('permissions_requested',kind === 'video' ? 'Allow camera access to show your video.' : 'Allow microphone access to speak.');
          // Independent requests let microphone-only calls work even if camera
          // permission is denied or the device has no camera (and vice versa).
          tracks = await sdk.createLocalTracks({
            audio:kind === 'audio' ? {echoCancellation:true,noiseSuppression:true,autoGainControl:true,channelCount:1,sampleRate:48000} : false,
            video:kind === 'video' ? {facingMode:'user',resolution:{...sdk.VideoPresets.h360.resolution,frameRate:15}} : false,
          });
          if (attempt !== publishingEpoch || room !== current) { tracks.forEach(track=>track.stop()); break; }
          for (const track of tracks) await current.localParticipant.publishTrack(track);
          if (attempt !== publishingEpoch || room !== current) {
            tracks.forEach(track=>{track.stop();current.localParticipant.unpublishTrack(track,true).catch(()=>{});});
            break;
          }
        } catch (error) {
          tracks.forEach(track=>{track.stop();current.localParticipant.unpublishTrack(track,true).catch(()=>{});});
          if (attempt === publishingEpoch && room === current) {
            if (kind === 'video') {desiredCamera = false;removeVideo(current.localParticipant.identity);emit('camera_error',mediaError(error));}
            else {desiredMicrophone = false;emit('microphone_error',mediaError(error));}
            wanted = desiredCamera || desiredMicrophone;
          }
        }
      }
      if (attempt === publishingEpoch && room === current) localState(current);
    });
    return mediaQueue;
  }
  function setPublishing(enabled) {
    return setLocalMedia(enabled,enabled);
  }
  window.addEventListener('pagehide',disconnect);
  window.__rallyMedia = {
    connect, disconnect, setPublishing, setLocalMedia, setParticipantMuted,
    layout(data) { layout = data; place(); },
    poll() { return JSON.stringify(events.splice(0)); },
  };
})();
