## Fix connections closed mid-transfer by the idle timeout

A connection could be closed by its idle timeout while it was still actively transferring data to a slow peer. A large transfer draining slowly to a slow reader looked idle even though data was still moving, so it was closed mid-transfer. A connection is now closed by the idle timeout only when no data has moved in either direction for the timeout.

