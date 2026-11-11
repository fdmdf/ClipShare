enum SyncingFileState {
  syncing(0),
  wait(1),
  error(2),
  done(3);

  final int order;

  const SyncingFileState(this.order);
}