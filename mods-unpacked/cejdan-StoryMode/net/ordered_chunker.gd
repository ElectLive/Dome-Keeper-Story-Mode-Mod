extends "res://systems/network/Chunker.gd"

# Vanilla's Chunker (#246): a message under MAX_CHUNK_SIZE goes out at once; a
# bigger one waits in a queue that sends CHUNKS_PER_FRAME chunks a frame for
# all peers together. So when a player joins (its stage data and map, ~70 KB)
# a big Data delta to a player already in the run waits behind them, the small
# deltas made after it go straight past, and when it lands its older values
# undo theirs: a value goes back for a moment, and a key nothing changes again
# stays wrong until StoryNet's resend (#242). For the boss state that means
# Velle's puppet torn down and rebuilt, the chase restarted.
#
# Here a Data message to a peer that already has a Data message queued joins
# the queue behind it instead of overtaking it. Everything else is vanilla.
# mod_main.gd puts this script on Network's chunker node (set_script, before
# any session), so the node keeps its name and RPC path.

static var held := 0    # small Data messages queued behind a big one (playtests)


func send(target_peer_id: int, request_type: ChunkRequestType, callable: Callable) -> void:
	if (request_type == ChunkRequestType.DATA_DELTA_SYNC or request_type == ChunkRequestType.DATA_FULL_SYNC) and _data_queued(target_peer_id):
		var data: PackedByteArray = var_to_bytes(callable.get_bound_arguments())
		if data.size() < MAX_CHUNK_SIZE:
			var chunks: Array[PackedByteArray] = [data]
			var id: int = _get_next_request_id()
			outgoing_rpcs[id] = OutgoingRPC.new(id, request_type, target_peer_id, chunks)
			held += 1
			return
	super.send(target_peer_id, request_type, callable)


# A request to a peer that has left is dropped: vanilla keeps sending its
# chunks, each one an "Attempt to call RPC with unknown peer ID" error (#249).
func _process(delta: float) -> void:
	if not outgoing_rpcs.is_empty() and multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		var peers: PackedInt32Array = multiplayer.get_peers()
		var me: int = multiplayer.get_unique_id()
		for id in outgoing_rpcs.keys():
			var to: int = outgoing_rpcs[id].target_peer_id
			if to != me and not peers.has(to):
				outgoing_rpcs.erase(id)
	super(delta)


func _data_queued(peer: int) -> bool:
	for r in outgoing_rpcs.values():
		if r.target_peer_id == peer and not r.is_sent() and (r.request_type == ChunkRequestType.DATA_DELTA_SYNC or r.request_type == ChunkRequestType.DATA_FULL_SYNC):
			return true
	return false
