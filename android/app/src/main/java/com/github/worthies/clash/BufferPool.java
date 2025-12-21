package com.github.worthies.clash;

import java.util.concurrent.ArrayBlockingQueue;

/**
 * Very small fixed-size buffer pool to reduce allocations under load.
 * Designed for brief reuse of byte[] buffers with a single fixed size.
 */
public class BufferPool {
    private final ArrayBlockingQueue<byte[]> pool;
    private final int bufSize;

    public BufferPool(int bufSize, int capacity) {
        this.bufSize = bufSize;
        this.pool = new ArrayBlockingQueue<>(Math.max(1, capacity));
        // prefill with some buffers
        for (int i = 0; i < Math.min(16, capacity); i++) pool.offer(new byte[bufSize]);
    }

    public byte[] acquire() {
        byte[] b = pool.poll();
        if (b == null) return new byte[bufSize];
        return b;
    }

    /** Acquire at least requested size. If requested <= bufSize returns a pooled buffer. */
    public byte[] acquireAtLeast(int size) {
        if (size <= bufSize) return acquire();
        return new byte[size];
    }

    public void release(byte[] b) {
        if (b == null) return;
        if (b.length != bufSize) return; // only pool buffers of managed size
        try { pool.offer(b); } catch (Exception ignore) {}
    }

    public int getBufSize() { return bufSize; }
}
