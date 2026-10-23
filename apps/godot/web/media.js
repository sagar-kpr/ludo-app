(() => {
  if (window.__rallyMedia) return;
  let room, sdk, sdkPromise, epoch = 0, publishingEpoch = 0, wanted = false;
  let layout = { visible: false, entries: [], width: 420, height: 860 };
  const events = [], videos = new Map(), audio = new Map();
  const emit = (state, message) => events.push({ state, message });
  const mediaError = error => {
    if (['NotAllowedError','PermissionDeniedError','SecurityError'].includes(error?.name)) return 'Camera or microphone permission was denied. Allow both in your browser settings, then tap the camera again.';
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
      element.dataset.playerId = identity;
      element.style.display = 'none';
      layer()?.append(element);
      audio.set(key, { element, track, identity });
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
    if (previous) { track.detach(previous.element); previous.element.remove(); audio.delete(track.sid); }
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
  function disconnect() {
    epoch++; publishingEpoch++; wanted = false;
    const previous = room; room = null;
    if (previous) { stopLocal(previous); previous.disconnect().catch(() => {}); }
    for (const identity of [...videos.keys()]) removeVideo(identity);
    for (const entry of audio.values()) { entry.track.detach(entry.element); entry.element.remove(); }
    audio.clear();
    document.querySelector('#rally-enable-voice')?.remove();
  }
  async function connect(credentials) {
    disconnect();
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
  async function setPublishing(enabled) {
    wanted = enabled;
    const attempt = ++publishingEpoch, current = room;
    if (!enabled) { stopLocal(current); emit('publishing_disabled','Camera and microphone off.'); return; }
    if (!current || current.state !== 'connected') return;
    let tracks = [];
    try {
      if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) throw {name:'SecurityError'};
      emit('permissions_requested','Allow camera and microphone access to join the call.');
      tracks = await sdk.createLocalTracks({
        audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true,channelCount:1,sampleRate:48000},
        video:{facingMode:'user',resolution:{...sdk.VideoPresets.h360.resolution,frameRate:15}},
      });
      if (attempt !== publishingEpoch || !wanted || room !== current) { tracks.forEach(track=>track.stop()); return; }
      for (const track of tracks) {
        if (attempt !== publishingEpoch || !wanted || room !== current) break;
        await current.localParticipant.publishTrack(track);
      }
      if (attempt !== publishingEpoch || !wanted || room !== current) {
        tracks.forEach(track=>{ track.stop(); current.localParticipant.unpublishTrack(track,true).catch(()=>{}); }); return;
      }
      emit('publishing_enabled','Camera and microphone on. Tap the camera again to turn both off.');
    } catch (error) {
      tracks.forEach(track=>{ track.stop(); current.localParticipant.unpublishTrack(track,true).catch(()=>{}); });
      if (attempt === publishingEpoch) { wanted = false; removeVideo(current.localParticipant.identity); emit('error',mediaError(error)); }
    }
  }
  window.addEventListener('pagehide',disconnect);
  window.__rallyMedia = {
    connect, disconnect, setPublishing,
    layout(data) { layout = data; place(); },
    poll() { return JSON.stringify(events.splice(0)); },
  };
})();
