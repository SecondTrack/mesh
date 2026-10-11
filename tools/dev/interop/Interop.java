// Gegenprobe: libsignal-protocol-java 2.8.1 (wie in der Android-App, MeshSignal.kt) gegen MeshSignal
// des iPods (tools/dev/signalinterop). Beide Richtungen, Reihenfolge durcheinander, Sicherheitsnummer.
//
//   tools/dev/interop/run.sh
import org.whispersystems.libsignal.*;
import org.whispersystems.libsignal.ecc.*;
import org.whispersystems.libsignal.protocol.*;
import org.whispersystems.libsignal.state.*;
import org.whispersystems.libsignal.state.impl.InMemorySignalProtocolStore;
import org.whispersystems.libsignal.util.KeyHelper;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.*;

public class Interop {
    static String tool, state;
    static final String IPOD_SEED = "0202020202020202020202020202020202020202020202020202020202020202";
    static final String IPOD = "1111111111111111111111111111111111111111111111111111111111111111";   // Pubkeys (nur Adressen)
    static final String DROID = "2222222222222222222222222222222222222222222222222222222222222222";
    static int ok = 0, bad = 0;

    static void check(boolean c, String name) { if (c) ok++; else { bad++; System.out.println("  FAIL " + name); } }

    static String ipod(String... args) throws Exception {
        List<String> cmd = new ArrayList<>(List.of(tool, state, IPOD_SEED));
        cmd.addAll(Arrays.asList(args));
        Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
        String out = new String(p.getInputStream().readAllBytes()).trim();
        p.waitFor();
        return out;
    }

    // --- Android-Seite, Zeile für Zeile wie MeshSignal.kt / MeshSignalStore.kt ---
    static byte[] sha256(byte[]... parts) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256"); for (byte[] b : parts) md.update(b); return md.digest();
    }
    static InMemorySignalProtocolStore store;
    static final Base64.Encoder URL_ENC = Base64.getUrlEncoder().withoutPadding();
    static final Base64.Decoder URL_DEC = Base64.getUrlDecoder();

    static IdentityKeyPair deriveIdentity(byte[] seed) throws Exception {
        byte[] scalar = sha256("mesh:signal:id:v1".getBytes(), seed);
        byte[] base = new byte[32]; base[0] = 9;
        byte[] pub32 = org.whispersystems.curve25519.Curve25519.getInstance(org.whispersystems.curve25519.Curve25519.BEST).calculateAgreement(base, scalar);
        byte[] ser = new byte[33]; ser[0] = 5; System.arraycopy(pub32, 0, ser, 1, 32);
        return new IdentityKeyPair(new IdentityKey(ser, 0), Curve.decodePrivatePoint(scalar));
    }
    static int regId(byte[] seed) throws Exception {
        byte[] r = sha256("mesh:signal:reg:v1".getBytes(), seed);
        return (((r[0] & 0xff) << 8 | (r[1] & 0xff)) & 0x3FFF) % 16380 + 1;
    }
    static String bundleWithFreshOneTime() throws Exception {
        SignedPreKeyRecord spk = store.loadSignedPreKey(1);
        int id = 1 + new Random().nextInt(0xFFFFFE);
        ECKeyPair kp = Curve.generateKeyPair();
        store.storePreKey(id, new PreKeyRecord(id, kp));
        ByteBuffer buf = ByteBuffer.allocate(4 + 4 + 33 + 33 + 64 + 4 + 33);
        buf.putInt(store.getLocalRegistrationId()); buf.putInt(1);
        buf.put(store.getIdentityKeyPair().getPublicKey().serialize());
        buf.put(spk.getKeyPair().getPublicKey().serialize()); buf.put(spk.getSignature());
        buf.putInt(id); buf.put(kp.getPublicKey().serialize());
        return URL_ENC.encodeToString(buf.array());
    }
    static PreKeyBundle parseBundle(String b64) throws Exception {
        byte[] raw = URL_DEC.decode(b64);
        ByteBuffer buf = ByteBuffer.wrap(raw);
        int regId = buf.getInt(), signedId = buf.getInt();
        byte[] idPub = new byte[33]; buf.get(idPub);
        byte[] sPub = new byte[33]; buf.get(sPub);
        byte[] sig = new byte[64]; buf.get(sig);
        int preKeyId = 0; ECPublicKey preKeyPub = null;
        if (raw.length >= 4 + 4 + 33 + 33 + 64 + 4 + 33) { preKeyId = buf.getInt(); byte[] otp = new byte[33]; buf.get(otp); preKeyPub = Curve.decodePoint(otp, 0); }
        return new PreKeyBundle(regId, 1, preKeyId, preKeyPub, signedId, Curve.decodePoint(sPub, 0), sig, new IdentityKey(idPub, 0));
    }
    static SignalProtocolAddress addr(String pk) { return new SignalProtocolAddress(pk, 1); }
    static String encrypt(String pk, String bundle, String text) throws Exception {
        SignalProtocolAddress a = addr(pk);
        if (!store.containsSession(a)) new SessionBuilder(store, a).process(parseBundle(bundle));
        CiphertextMessage msg = new SessionCipher(store, a).encrypt(text.getBytes("UTF-8"));
        return "sg1:" + (msg.getType() == CiphertextMessage.PREKEY_TYPE ? "p" : "m") + ":" + Base64.getEncoder().encodeToString(msg.serialize());
    }
    static String decrypt(String pk, String content) {
        try {
            String[] parts = content.split(":", 3);
            byte[] bytes = Base64.getDecoder().decode(parts[2]);
            SessionCipher c = new SessionCipher(store, addr(pk));
            byte[] plain = parts[1].equals("p") ? c.decrypt(new PreKeySignalMessage(bytes)) : c.decrypt(new SignalMessage(bytes));
            return new String(plain, "UTF-8");
        } catch (Exception e) { return "FEHLER " + e.getClass().getSimpleName() + ": " + e.getMessage(); }
    }
    static byte[] sha512(byte[]... parts) throws Exception { MessageDigest md = MessageDigest.getInstance("SHA-512"); for (byte[] b : parts) md.update(b); return md.digest(); }
    static byte[] hex(String s) { byte[] b = new byte[s.length() / 2]; for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(s.substring(2 * i, 2 * i + 2), 16); return b; }
    static String safetyNumber(String myPk, String peerPk, String peerBundle) throws Exception {
        byte[] myId = store.getIdentityKeyPair().getPublicKey().serialize();
        byte[] peerId = Arrays.copyOfRange(URL_DEC.decode(peerBundle), 8, 41);
        byte[] a = sha512(myId, hex(myPk)), b = sha512(peerId, hex(peerPk));
        int cmp = 0; for (int i = 0; i < a.length && cmp == 0; i++) cmp = (a[i] & 0xff) - (b[i] & 0xff);
        byte[] h = cmp <= 0 ? sha512(a, b) : sha512(b, a);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 12; i++) {
            long v = 0; for (int j = 0; j < 5; j++) v = (v << 8) | (h[i * 5 + j] & 0xff);
            if (i > 0) sb.append(' ');
            sb.append(String.format("%05d", v % 100000));
        }
        return sb.toString();
    }

    public static void main(String[] args) throws Exception {
        tool = args[0]; state = args[1];
        // Ein Android-Seed, dessen Signatur gültig ist (Androids Ableitung ist nicht geclampt).
        byte[] seed = null;
        for (int s = 1; s < 200 && seed == null; s++) {
            byte[] cand = new byte[32]; Arrays.fill(cand, (byte) s);
            IdentityKeyPair id = deriveIdentity(cand);
            SignedPreKeyRecord spk = KeyHelper.generateSignedPreKey(id, 1);
            if (Curve.verifySignature(id.getPublicKey().getPublicKey(), spk.getKeyPair().getPublicKey().serialize(), spk.getSignature())) {
                seed = cand;
                store = new InMemorySignalProtocolStore(id, regId(cand));
                store.storeSignedPreKey(1, spk);
            }
        }

        // 1) Android beginnt mit dem Bundle des iPods (mit Einmal-Schlüssel)
        String ipodBundle = ipod("bundle");
        String c1 = encrypt(IPOD, ipodBundle, "Hallo iPod, hier Android 📱");
        String c2 = encrypt(IPOD, ipodBundle, "zweite Nachricht");
        check(c1.startsWith("sg1:p:"), "android sendet PreKeySignalMessage");
        check(ipod("decrypt", DROID, c2).equals("zweite Nachricht"), "iPod liest die zweite zuerst");
        check(ipod("decrypt", DROID, c1).equals("Hallo iPod, hier Android 📱"), "iPod liest die erste");
        String r1 = ipod("encrypt", DROID, "-", "Antwort vom iPod ✅");
        check(r1.startsWith("sg1:m:"), "iPod antwortet mit SignalMessage");
        check(decrypt(IPOD, r1).equals("Antwort vom iPod ✅"), "Android liest die Antwort: " + decrypt(IPOD, r1));
        List<String> batch = new ArrayList<>();
        for (int i = 0; i < 12; i++) batch.add(encrypt(IPOD, ipodBundle, "a" + i));
        boolean all = true;
        for (int i = 11; i >= 0; i--) all &= ipod("decrypt", DROID, batch.get(i)).equals("a" + i);
        check(all, "12 Nachrichten rückwärts");
        for (int i = 0; i < 5; i++) {
            String r = ipod("encrypt", DROID, "-", "i" + i);
            all &= decrypt(IPOD, r).equals("i" + i);
            String c = encrypt(IPOD, ipodBundle, "d" + i);
            all &= ipod("decrypt", DROID, c).equals("d" + i);
        }
        check(all, "Ping-Pong mit Ratchet-Schritten");

        // 2) Der iPod beginnt mit dem Bundle von Android (neuer Kontakt, frischer Zustand)
        String droid2 = "3333333333333333333333333333333333333333333333333333333333333333";
        String androidBundle = bundleWithFreshOneTime();
        String i1 = ipod("encrypt", droid2, androidBundle, "iPod fängt an");
        check(i1.startsWith("sg1:p:"), "iPod sendet PreKeySignalMessage: " + i1.substring(0, Math.min(20, i1.length())));
        String i2 = ipod("encrypt", droid2, androidBundle, "und noch eine");
        check(decrypt(droid2, i2).equals("und noch eine"), "Android liest die zweite zuerst: " + decrypt(droid2, i2));
        check(decrypt(droid2, i1).equals("iPod fängt an"), "Android liest die erste");
        String a1 = encrypt(droid2, androidBundle, "Android antwortet");
        check(a1.startsWith("sg1:m:") && ipod("decrypt", droid2, a1).equals("Android antwortet"), "iPod liest Androids Antwort");
        String i3 = ipod("encrypt", droid2, "-", "läuft");
        check(i3.startsWith("sg1:m:") && decrypt(droid2, i3).equals("läuft"), "danach normale Nachrichten");

        // 3) Große Nachricht (Bild über Signal, kein 64-KB-Limit)
        StringBuilder big = new StringBuilder("mesh:img");
        while (big.length() < 200000) big.append("QUJDREVGR0hJSktMTU5PUA");
        String bigC = encrypt(IPOD, ipodBundle, big.toString());
        check(ipod("decrypt", DROID, bigC).equals(big.toString()), "200 KB über Signal");

        // 4) Sicherheitsnummer gleich
        String mine = ipod("safety", DROID, IPOD, androidBundle);
        String theirs = safetyNumber(DROID, IPOD, ipod("static"));
        check(mine.equals(theirs), "Sicherheitsnummer: iPod " + mine + " / Android " + theirs);

        System.out.println("== " + ok + " ok, " + bad + " fehlgeschlagen ==");
        System.exit(bad == 0 ? 0 : 1);
    }
}
