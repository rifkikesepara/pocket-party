import asyncio
import socket
from bleak import BleakClient, BleakScanner

SERVICE_UUID = "A7C30001-5A2B-4C9E-9D1A-8F0000000001"
CHAR_UUID = "A7C30002-5A2B-4C9E-9D1A-8F0000000001"
GODOT_ADDR = ("127.0.0.1", 42425)
BRIDGE_PORT = 42426


def make_ping_packet(sender_id: int = 1) -> bytes:
    pkt = bytearray(16)
    pkt[0] = 0x01  # CALIBRATION
    pkt[1] = sender_id
    pkt[2] = 0xFF
    chk = 0
    for b in pkt[:15]:
        chk ^= b
    pkt[15] = chk
    return bytes(pkt)


async def run_bridge() -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", BRIDGE_PORT))
    sock.setblocking(False)
    print(f"[BLE Bridge] UDP dinleniyor: 127.0.0.1:{BRIDGE_PORT} -> Godot {GODOT_ADDR}")

    while True:
        print("[BLE Bridge] PocketParty BLE cihazi araniyor...")
        device = await BleakScanner.find_device_by_filter(
            lambda _d, adv: SERVICE_UUID.lower() in [u.lower() for u in (adv.service_uuids or [])],
            timeout=5.0,
        )
        if not device:
            continue

        print(f"[BLE Bridge] Bulundu: {device.name or 'PocketParty'} ({device.address}), baglaniliyor...")
        try:
            async with BleakClient(device) as client:
                print("[BLE Bridge] BLE baglantisi kuruldu!")
                sock.sendto(make_ping_packet(), GODOT_ADDR)

                def on_notify(_sender: int, data: bytearray) -> None:
                    if len(data) == 16:
                        sock.sendto(bytes(data), GODOT_ADDR)

                await client.start_notify(CHAR_UUID, on_notify)

                while client.is_connected:
                    try:
                        data, _addr = sock.recvfrom(64)
                        if len(data) == 16:
                            await client.write_gatt_char(CHAR_UUID, data, response=False)
                    except BlockingIOError:
                        await asyncio.sleep(0.01)
        except Exception as exc:
            print(f"[BLE Bridge] Baglanti kesildi ({exc}), yeniden deneniyor...")
            await asyncio.sleep(1.0)


if __name__ == "__main__":
    asyncio.run(run_bridge())
