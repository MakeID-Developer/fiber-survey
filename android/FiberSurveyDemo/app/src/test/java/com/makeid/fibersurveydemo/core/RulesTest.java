package com.makeid.fibersurveydemo.core;

import org.junit.Test;
import java.util.Arrays;
import static org.junit.Assert.*;

/** Real Java rules tests, written but not compiled/executed under the no-build policy. */
public final class RulesTest {
    @Test public void filterPreservesSymbolsAndLeadingZeros() {
        assertEquals(Arrays.asList("000011", "A-1", "A1", "11"),
                DetectorFilterParser.parse(" 000011，A-1; A1；11 "));
        assertTrue(DetectorFilterParser.parse(" ， ; \n").isEmpty());
    }
    @Test public void hostIdIsTextNotANumber() {
        assertEquals("000002", DetectorFilterParser.hostId(" TR-FID-000002 "));
        assertEquals("000002", DetectorFilterParser.hostId("tr-fid-000002"));
    }
    @Test public void bufferIsBoundedAndNewestFirst() {
        BoundedLogStore<Integer> store = new BoundedLogStore<>(2);
        store.add(1); store.add(2); store.add(3);
        assertEquals(Arrays.asList(3, 2),store.snapshot());
        store.clear(); assertTrue(store.snapshot().isEmpty());
    }
    @Test public void operationCompletesOnceAndRejectsLateCallbacks() {
        SessionState state = new SessionState();
        long first = state.next();
        assertTrue(state.isCurrent(first));
        state.next(); assertFalse(state.isCurrent(first));
        long token=state.beginCommand();
        assertTrue(state.finishCommand(token));
        assertFalse(state.finishCommand(token));
        token=state.beginCommand(); state.next();
        assertFalse(state.finishCommand(token));
    }
}
