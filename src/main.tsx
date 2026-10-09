import React, { useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Camera, Check, ChevronRight, Copy, Crown, MessageCircle, Mic, Play, Shield, Sparkles, Volume2, Wifi } from 'lucide-react';
import { createGame, type Color, type GameState } from '../packages/game-engine/src/index';
import { connectRealtime, type RealtimeEvent } from './realtime';
import { Board } from './Board';
import { Dice } from './Dice';
import { createDicePresentation, DICE_ROLL_MS } from '../packages/shared/src/dice';
import './pawns.css';
import './styles.css';

const players = [
  { id: 'you', name: 'You', color: 'coral' as Color, ready: true },
  { id: 'maya', name: 'Maya', color: 'sun' as Color, ready: true },
  { id: 'liam', name: 'Liam', color: 'mint' as Color, ready: true },
];

function App() {
  const [screen, setScreen] = useState<'home' | 'join' | 'lobby' | 'game'>('home');
  const [joinCode, setJoinCode] = useState('');
  const [roomError, setRoomError] = useState('');
  const [pending, setPending] = useState(false);
  const [roomCode, setRoomCode] = useState('NOVA-248');
  const [muted, setMuted] = useState(false);
  const [camera, setCamera] = useState(false);
  const [chat, setChat] = useState('');
  const [messages, setMessages] = useState<string[]>([]);
  const [lastRoll, setLastRoll] = useState<number | null>(null);
  const [notice, setNotice] = useState('');
  const [rollColor, setRollColor] = useState<Color | null>(null);
  const [diceRolling, setDiceRolling] = useState(false);
  const [animating, setAnimating] = useState(false);
  const animationTimer = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const [state, setState] = useState<GameState>(() => createGame(players));
  const [serverConnected, setServerConnected] = useState(false);
  const realtime = React.useRef<ReturnType<typeof connectRealtime> | null>(null);
  const serverPlayerId = React.useRef<string>('');
  const serverTokenIds = React.useRef(new Map<string, string>());
  const current = state.players.find((player) => player.id === state.currentPlayer);
  const palette = { coral: '#ff6e73', sun: '#ffbf4b', mint: '#55d8b5', violet: '#9175ff' };
  const diceColor = (animating && rollColor) || current?.color || 'coral';
  const highlightColor = diceRolling || animating || state.phase === 'moving' ? rollColor : null;
  const available = useMemo(() => state.tokens.filter((token) => token.color === 'coral'), [state.tokens]);

  const requestRoom = (join: boolean) => {
    if (pending) return;
    setRoomError('');
    if (!serverConnected) { setRoomError('Server disconnected. Start npm run server and refresh.'); return; }
    if (join && !joinCode.trim()) { setRoomError('Enter your friend’s room code.'); return; }
    setPending(true);
    realtime.current?.send(join ? { type: 'JOIN_ROOM', code: joinCode.trim().toUpperCase(), name: 'Guest' } : { type: 'CREATE_ROOM', name: 'Guest' });
  };
  const openLobby = () => requestRoom(false);
  const openGame = () => { realtime.current?.send({ type: 'START_GAME' }); };
  const dice = () => { if (!animating) realtime.current?.send({ type: 'ROLL_DICE' }); };
  const move = (id: string) => { if (!animating) realtime.current?.send({ type: 'MOVE_TOKEN', tokenId: serverTokenIds.current.get(id) || id }); };
  React.useEffect(() => {
    const hold = (ms: number) => {
      setAnimating(true);
      if (animationTimer.current) clearTimeout(animationTimer.current);
      animationTimer.current = setTimeout(() => { setAnimating(false); setNotice((text) => text === 'Token moving…' || text === 'Moving your only available token.' ? 'Move complete.' : text); }, ms+80);
    };
    const presentation = createDicePresentation<RealtimeEvent>((event) => {
      if (event.type === 'DICE_ROLLED') { setDiceRolling(true); setRollColor(event.color as Color); hold(DICE_ROLL_MS); }
      if (event.type === 'TOKEN_MOVED') hold(Number(event.durationMs)+Number(event.delayMs));
      handleEvent(event);
    }, () => setDiceRolling(false));
    const handleEvent = (event: RealtimeEvent) => {
        if (event.type === 'CONNECTED') serverPlayerId.current = String(event.playerId || '');
        if ((event.type === 'ROOM_CREATED' || event.type === 'ROOM_JOINED') && event.roomCode) {
          setRoomCode(String(event.roomCode)); setPending(false); setRoomError(''); setScreen('lobby');
        }
        if (event.type === 'DICE_ROLLED') { setLastRoll(Number(event.value)); setNotice(event.skipped ? 'Rolled ' + event.value + '. No legal move — turn passed. Base tokens need a six.' : event.automatic ? 'Rolled ' + event.value + '. Moving your only available token.' : 'Rolled ' + event.value + '. Select a highlighted pawn.'); }
        if (event.type === 'TOKEN_MOVED') setNotice(event.automatic ? 'Moving your only available token.' : 'Token moving…');
        if (event.type === 'CHAT') setMessages((all) => [...all, String(event.name || 'Guest') + ': ' + String(event.text)].slice(-100));
        if (event.type === 'ERROR') { setRoomError(String(event.message)); setPending(false); }
        if (event.type === 'STATE') {
          const incoming = event.state as GameState;
          const self = serverPlayerId.current;
          serverTokenIds.current.clear();
          const tokens = incoming.tokens.map((token) => {
            const id = token.id.startsWith(self + '-') ? 'you' + token.id.slice(self.length) : token.id;
            serverTokenIds.current.set(id, token.id);
            return { ...token, id };
          });
          const normalized: GameState = { ...incoming, tokens, players: incoming.players.map((player) => ({ ...player, id: player.id === self ? 'you' : player.id })), currentPlayer: incoming.currentPlayer === self ? 'you' : incoming.currentPlayer, winner: incoming.winner === self ? 'you' : incoming.winner };
          setState(normalized); setPending(false);
          setScreen(normalized.phase === 'lobby' ? 'lobby' : 'game');
        }
    };
    try {
      realtime.current = connectRealtime(presentation.receive, (online) => { setServerConnected(online); if (!online) setPending(false); });
    } catch { setServerConnected(false); }
    return () => { presentation.dispose(); realtime.current?.close(); if (animationTimer.current) clearTimeout(animationTimer.current); };
  }, []);

  return <main className="app-shell">
    {roomError && <p role="alert" style={{ color: '#ffbf4b' }}>{roomError}</p>}
    {screen === 'join' && <section className="lobby panel page-enter">
      <p className="eyebrow">JOIN YOUR FRIENDS</p><h2>Enter a room code</h2>
      <form onSubmit={(e) => { e.preventDefault(); requestRoom(true); }}>
        <label htmlFor="room-code-input">Room code</label>
        <input id="room-code-input" value={joinCode} onChange={(e) => setJoinCode(e.target.value)} placeholder="AB12-CD34" autoFocus maxLength={32} style={{ padding: 16, margin: 16, borderRadius: 12 }} />
        <button className="primary-button" disabled={pending}>{pending ? 'Joining…' : 'Join room'}</button>
      </form>
      <button className="secondary-button" onClick={() => setScreen('home')} style={{ marginTop: 16 }}>Back</button>
    </section>}
    <div className="aurora aurora-one" /><div className="aurora aurora-two" />
    <header className="topbar"><div className="brand"><span className="brand-mark"><Sparkles size={18} /></span><span>RALLY <em>LUDO</em></span></div><div className="top-actions"><span className={`connection ${serverConnected ? '' : 'offline'}`}><Wifi size={14} /> {serverConnected ? 'Live' : 'Demo mode'}</span><button className="avatar">AG</button></div></header>
    {screen === 'home' && <section className="home page-enter"><div className="hero-copy"><p className="eyebrow"><Sparkles size={14} /> REAL-TIME PLAYGROUND</p><h1>Roll into<br /><span>the moment.</span></h1><p className="hero-text">A premium Ludo table for your favorite people. No downloads, no waiting — just share a room and play.</p><div className="home-actions"><button className="primary-button" onClick={openLobby}><Play size={18} fill="currentColor" /> Create a room <ChevronRight size={18} /></button><button className="secondary-button" onClick={() => { setRoomError(''); setScreen('join'); }}>Join with code</button></div><div className="trust-row"><Shield size={16} /> Private rooms · Guest friendly · Cross-platform</div></div><div className="hero-card"><div className="card-glow" /><div className="mini-board"><Board state={state} preview /></div><div className="float-pill pill-one"><span className="dot mint" /> Maya joined</div><div className="float-pill pill-two"><Sparkles size={14} /> Smooth play</div></div></section>}
    {screen === 'lobby' && <section className="lobby page-enter"><div className="section-heading"><div><p className="eyebrow">ROOM LOBBY</p><h2>Bring your crew.</h2></div><button className="icon-button" onClick={() => navigator.clipboard?.writeText(roomCode)} title="Copy room code"><Copy size={18} /></button></div><div className="lobby-grid"><div className="panel players-panel"><div className="panel-title"><span>Players <b>{state.players.length} / 4</b></span><span className="live-dot">LIVE</span></div><div className="player-list">{state.players.map((player, index) => <div className="player-row" key={player.id}><div className={`player-avatar ${player.color}`}>{player.name.slice(0, 1)}</div><div className="player-info"><strong>{player.name}{index === 0 && <small> YOU</small>}</strong><span>{index === 0 ? 'Room host' : 'Ready to play'}</span></div><Check className="ready" size={18} /></div>)}<div className="empty-seat"><span>+</span><div><strong>Waiting for a friend</strong><span>Share your room link</span></div></div></div><p>{state.players[0]?.id !== 'you' ? 'Waiting for the host to start. The board will open automatically.' : state.players.length < 2 ? 'Waiting for a friend. Share your room code.' : 'Your friends joined. Start when everyone is ready.'}</p>{state.players[0]?.id === 'you' && <button className="primary-button full" disabled={!serverConnected || state.players.length < 2} onClick={openGame}>Start the game <ChevronRight size={18} /></button>}</div><div className="panel invite-panel"><p className="eyebrow">ROOM CODE</p><div className="room-code">{roomCode}</div><p>Share this code or the link below with your friends.</p><button className="copy-link" onClick={() => navigator.clipboard?.writeText(roomCode)}><Copy size={15} /> Copy invite link</button><div className="guest-note"><Sparkles size={16} /><span>Friends can join as guests<br /><b>No account required</b></span></div></div></div></section>}
    {screen === 'game' && <section className="game-layout page-enter"><div className="game-top"><div><p className="eyebrow">ROOM {roomCode}</p><h2>Saturday night table</h2></div><div className="game-top-actions"><span className="connection"><Wifi size={14} /> Synced</span><button className="icon-button"><MessageCircle size={18} /></button></div></div><div className="game-grid"><div className="board-column"><div className="turn-banner"><div className={`player-avatar ${current?.color ?? 'coral'}`}>{current?.name[0]}</div><div><strong>{current?.id === 'you' ? 'Your turn' : `${current?.name}'s turn`}</strong><span>{state.phase === 'finished' ? 'Match complete' : state.currentPlayer !== 'you' ? 'Wait for this player to finish their turn.' : state.phase === 'moving' ? 'Select one of your highlighted tokens.' : 'Tap Roll dice. Six brings a token out of base.'}</span></div></div><div className="board-wrap"><Board state={state} highlightColor={highlightColor} onMove={move} connected={serverConnected && !animating} /></div><div className="game-controls"><button className={`dice-button ${state.phase === 'rolling' && state.currentPlayer === 'you' ? 'ready' : ''}`} style={{ '--turn-color': palette[diceColor] } as React.CSSProperties} onClick={dice} disabled={!serverConnected || animating || state.phase !== 'rolling' || state.currentPlayer !== 'you'}><Dice value={lastRoll} rolling={diceRolling} /><small>{diceRolling ? 'ROLLING…' : animating ? 'MOVING…' : state.phase === 'rolling' ? 'ROLL DICE' : 'CHOOSE PAWN'}</small></button><div className="token-hint">{state.phase === 'moving' ? <><Sparkles size={16} /> Choose a glowing token to move</> : <><Volume2 size={16} /> {notice || 'Watch the turn indicator'}</>}</div></div></div><aside className="side-panel"><div className="video-card"><div className="video-header"><span>LIVE ROOM</span><span className="live-dot">● 3</span></div><div className="video-grid"><div className="video-tile you-tile"><span>AG</span><small>You</small></div><div className="video-tile maya-tile"><span>M</span><small>Maya</small></div><div className="video-tile liam-tile"><span>L</span><small>Liam</small></div></div><div className="media-actions"><button className={muted ? 'active' : ''} onClick={() => setMuted(!muted)}><Mic size={16} /></button><button className={camera ? 'active' : ''} onClick={() => setCamera(!camera)}><Camera size={16} /></button></div></div><div className="chat-card"><div className="chat-header"><span><MessageCircle size={16} /> Table chat</span><span>3 online</span></div><div className="messages">{messages.map((message, i) => <p key={i}>{message}</p>)}</div><form className="chat-input" onSubmit={(e) => { e.preventDefault(); if (chat.trim()) { realtime.current?.send({ type: 'CHAT', text: chat }); setChat(''); } }}><input value={chat} onChange={(e) => setChat(e.target.value)} placeholder="Say something..." /><button><ChevronRight size={17} /></button></form></div></aside></div></section>}
    <footer><span>RALLY LUDO © 2026</span><span>Built for the people at your table</span></footer>
  </main>;
}

createRoot(document.getElementById('root')!).render(<App />);
