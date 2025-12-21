package com.github.worthies.clash;

import org.junit.Test;
import static org.junit.Assert.*;

import java.lang.reflect.Method;

public class ClashVpnServiceTest {

    @Test
    public void testIpToBytesIpv4() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        Method m = ClashVpnService.class.getDeclaredMethod("ipToBytes", String.class);
        m.setAccessible(true);
        byte[] b = (byte[]) m.invoke(svc, "192.168.0.1");
        assertNotNull(b);
        assertEquals(4, b.length);
        assertEquals((byte)192, b[0]);
    }

    @Test
    public void testIpToBytesIpv6() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        Method m = ClashVpnService.class.getDeclaredMethod("ipToBytes", String.class);
        m.setAccessible(true);
        byte[] b = (byte[]) m.invoke(svc, "2001:db8::1");
        assertNotNull(b);
        assertEquals(16, b.length);
    }

    @Test
    public void testLooksLikeHttp() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        Method m = ClashVpnService.class.getDeclaredMethod("looksLikeHttp", byte[].class);
        m.setAccessible(true);
        assertTrue((Boolean) m.invoke(svc, new Object[] { "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".getBytes("US-ASCII") }));
        assertFalse((Boolean) m.invoke(svc, new Object[] { "\u0001\u0002\u0003\u0004".getBytes("US-ASCII") }));
    }

    @Test
    public void testExtractTlsSni() throws Exception {
        // Build a minimal ClientHello with SNI extension for example.com
        java.io.ByteArrayOutputStream bout = new java.io.ByteArrayOutputStream();
        // TLS record header: type(1)=22, ver=0x0301, length=... (placeholder)
        bout.write(0x16); bout.write(0x03); bout.write(0x01);
        // We'll append handshake then backfill length
        java.io.ByteArrayOutputStream hs = new java.io.ByteArrayOutputStream();
        hs.write(0x01); // client hello
        // placeholder for 3 byte length
        hs.write(new byte[] {0x00, 0x00, 0x00});
        // client version
        hs.write(0x03); hs.write(0x03);
        // random (32 bytes)
        hs.write(new byte[32]);
        // session id len
        hs.write(0x00);
        // cipher suites len (2 bytes) + one suite
        hs.write(0x00); hs.write(0x02); hs.write(0x00); hs.write(0x2f);
        // comp methods len + comp
        hs.write(0x01); hs.write(0x00);
        // extensions length placeholder
        java.io.ByteArrayOutputStream exts = new java.io.ByteArrayOutputStream();
        // server_name extension (type 0)
        java.io.ByteArrayOutputStream sn = new java.io.ByteArrayOutputStream();
        // list length
        byte[] hostname = "example.com".getBytes("US-ASCII");
        int nameLen = hostname.length;
        byte[] nameList = new byte[3 + nameLen];
        nameList[0] = 0x00; // name type 0
        nameList[1] = (byte)((nameLen >> 8) & 0xFF);
        nameList[2] = (byte)(nameLen & 0xFF);
        System.arraycopy(hostname, 0, nameList, 3, nameLen);
        // server_name list length (2 bytes)
        sn.write((nameList.length >> 8) & 0xFF);
        sn.write(nameList.length & 0xFF);
        sn.write(nameList);
        // extension header: type=0, len=sn.size()
        exts.write(0x00); exts.write(0x00);
        int l = sn.size();
        exts.write((l >> 8) & 0xFF); exts.write(l & 0xFF);
        exts.write(sn.toByteArray());

        byte[] extsb = exts.toByteArray();
        // write extensions length (2 bytes)
        hs.write((extsb.length >> 8) & 0xFF); hs.write(extsb.length & 0xFF);
        hs.write(extsb);

        byte[] hsb = hs.toByteArray();
        // fix handshake length
        int hsLen = hsb.length - 4; // minus the 1 + 3 length bytes
        hsb[1] = (byte)((hsLen >> 16) & 0xFF);
        hsb[2] = (byte)((hsLen >> 8) & 0xFF);
        hsb[3] = (byte)(hsLen & 0xFF);

        // now total record length
        int recLen = hsb.length;
        bout.write((recLen >> 8) & 0xFF); bout.write(recLen & 0xFF);
        bout.write(hsb);

        byte[] raw = bout.toByteArray();

        ClashVpnService svc = new ClashVpnService();
        Method m = ClashVpnService.class.getDeclaredMethod("extractTlsSni", byte[].class);
        m.setAccessible(true);
        String sni = (String) m.invoke(svc, new Object[] { raw });
        assertEquals("example.com", sni);
    }

    @Test
    public void testBuildIpv6TcpPacketAndChecksum() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        java.lang.reflect.Method m = ClashVpnService.class.getDeclaredMethod("buildIpv6TcpPacket", String.class, String.class, int.class, int.class, long.class, long.class, byte.class, byte[].class);
        m.setAccessible(true);
        byte[] pkt = (byte[]) m.invoke(svc, "2001:db8::1", "2001:db8::2", 12345, 80, 100L, 1L, (byte)0x18, "hello".getBytes("US-ASCII"));
        assertNotNull(pkt);
        // IPv6 header length should be 40
        assertTrue(pkt.length >= 60);
        // TCP checksum bytes (offsets 40+16) should not both be zero
        int chkOff = 40 + 16;
        assertNotEquals(0, ((pkt[chkOff] & 0xFF) << 8) | (pkt[chkOff+1] & 0xFF));
    }

    @Test
    public void testBuildIpv4TcpPacketAndChecksum() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        java.lang.reflect.Method m = ClashVpnService.class.getDeclaredMethod("buildIpv4TcpPacket", String.class, String.class, int.class, int.class, long.class, long.class, byte.class, byte[].class);
        m.setAccessible(true);
        byte[] pkt = (byte[]) m.invoke(svc, "10.0.0.1", "10.0.0.2", 50000, 80, 123L, 1L, (byte)0x18, "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".getBytes("US-ASCII"));
        assertNotNull(pkt);
        assertTrue(pkt.length > 40);
        int ipChk = ((pkt[10] & 0xFF) << 8) | (pkt[11] & 0xFF);
        assertNotEquals(0, ipChk);
        int tcpChk = ((pkt[36] & 0xFF) << 8) | (pkt[37] & 0xFF);
        assertNotEquals(0, tcpChk);
    }

    @Test
    public void testBuildIpv4UdpPacketAndChecksum() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        java.lang.reflect.Method m = ClashVpnService.class.getDeclaredMethod("buildIpv4UdpPacket", String.class, String.class, int.class, int.class, byte[].class);
        m.setAccessible(true);
        byte[] pkt = (byte[]) m.invoke(svc, "10.0.0.1", "10.0.0.2", 50000, 53, "hello".getBytes("US-ASCII"));
        assertNotNull(pkt);
        assertTrue(pkt.length >= 28);
        int ipChk = ((pkt[10] & 0xFF) << 8) | (pkt[11] & 0xFF);
        assertNotEquals(0, ipChk);
        int udpLen = ((pkt[24] & 0xFF) << 8) | (pkt[25] & 0xFF);
        assertEquals(8 + 5, udpLen);
    }

    @Test
    public void testBufferPool() throws Exception {
        BufferPool bp = new BufferPool(256, 4);
        byte[] a = bp.acquire();
        assertNotNull(a);
        assertEquals(256, a.length);
        bp.release(a);
        byte[] b = bp.acquire();
        assertNotNull(b);
        assertEquals(256, b.length);
    }

    @Test
    public void testBuildIpv6UdpPacketAndChecksum() throws Exception {
        ClashVpnService svc = new ClashVpnService();
        java.lang.reflect.Method m = ClashVpnService.class.getDeclaredMethod("buildIpv6UdpPacket", String.class, String.class, int.class, int.class, byte[].class);
        m.setAccessible(true);
        byte[] pkt = (byte[]) m.invoke(svc, "2001:db8::1", "2001:db8::2", 12345, 53, "hello".getBytes("US-ASCII"));
        assertNotNull(pkt);
        assertTrue(pkt.length >= 48);
        // UDP length at offsets 40+4 and 40+5
        int udpLen = ((pkt[44] & 0xFF) << 8) | (pkt[45] & 0xFF);
        assertEquals(8 + 5, udpLen);
    }

    @Test
    public void testRetransmitPendingSegments() throws Exception {
        // Simplified test: verifies SentSegment class fields exist and are accessible
        java.lang.Class<?> segClass = java.lang.Class.forName("com.github.worthies.clash.ClashVpnService$SentSegment");
        java.lang.reflect.Constructor segCtor = segClass.getDeclaredConstructor(long.class, byte[].class, int.class);
        segCtor.setAccessible(true);
        byte[] pkt = new byte[60];
        Object seg = segCtor.newInstance(123L, pkt, 10);

        // Verify fields exist
        java.lang.reflect.Field seqField = segClass.getDeclaredField("seq"); seqField.setAccessible(true);
        long seq = (long) seqField.get(seg);
        assertEquals(123L, seq);

        java.lang.reflect.Field payloadLenField = segClass.getDeclaredField("payloadLen"); payloadLenField.setAccessible(true);
        int payloadLen = (int) payloadLenField.get(seg);
        assertEquals(10, payloadLen);

        java.lang.reflect.Field attemptsField = segClass.getDeclaredField("attempts"); attemptsField.setAccessible(true);
        int attempts = (int) attemptsField.get(seg);
        assertEquals(1, attempts);
    }
}
