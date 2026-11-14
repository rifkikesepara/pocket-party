#import "PocketPartyBLE.hpp"

#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <PhotosUI/PhotosUI.h>
#import <UIKit/UIKit.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

static NSString *const kPocketPartyServiceUUID = @"A7C30001-5A2B-4C9E-9D1A-8F0000000001";
static NSString *const kPocketPartyCharUUID = @"A7C30002-5A2B-4C9E-9D1A-8F0000000001";

@interface PPBLEManager : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate, PHPickerViewControllerDelegate>

@property (nonatomic, assign) godot::PocketPartyBLE *cppOwner;
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBMutableCharacteristic *localCharacteristic;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CBPeripheral *> *discoveredPeripherals;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CBCharacteristic *> *remoteCharacteristics;
@property (nonatomic, strong) dispatch_queue_t bleQueue;
@property (nonatomic, assign) BOOL isStarted;
@property (nonatomic, assign) BOOL photoPickerBusy;

- (instancetype)initWithOwner:(godot::PocketPartyBLE *)owner;
- (void)start;
- (void)stop;
- (void)broadcastPacket:(NSData *)data;
- (void)pickAvatarPhoto;
- (void)finishAvatarPhoto:(NSData *)data failed:(BOOL)failed;

@end

@implementation PPBLEManager

- (instancetype)initWithOwner:(godot::PocketPartyBLE *)owner {
	self = [super init];
	if (self) {
		_cppOwner = owner;
		_discoveredPeripherals = [NSMutableDictionary dictionary];
		_remoteCharacteristics = [NSMutableDictionary dictionary];
		_bleQueue = dispatch_queue_create("com.pocketparty.ble", DISPATCH_QUEUE_SERIAL);
		_isStarted = NO;
	}
	return self;
}

- (void)start {
	if (_isStarted) {
		return;
	}
	_isStarted = YES;
	_centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:_bleQueue];
	_peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:_bleQueue];
}

- (void)stop {
	if (!_isStarted) {
		return;
	}
	_isStarted = NO;
	[_centralManager stopScan];
	[_peripheralManager stopAdvertising];
	for (CBPeripheral *p in _discoveredPeripherals.allValues) {
		[_centralManager cancelPeripheralConnection:p];
	}
	[_discoveredPeripherals removeAllObjects];
	[_remoteCharacteristics removeAllObjects];
}

- (void)broadcastPacket:(NSData *)data {
	if (!data || data.length == 0) {
		return;
	}
	dispatch_async(_bleQueue, ^{
		if (self.localCharacteristic && self.peripheralManager.state == CBManagerStatePoweredOn) {
			[self.peripheralManager updateValue:data
							  forCharacteristic:self.localCharacteristic
						   onSubscribedCentrals:nil];
		}
		for (NSUUID *uuid in self.remoteCharacteristics) {
			CBPeripheral *peripheral = self.discoveredPeripherals[uuid];
			CBCharacteristic *ch = self.remoteCharacteristics[uuid];
			if (peripheral && ch && peripheral.state == CBPeripheralStateConnected) {
				CBCharacteristicWriteType writeType =
					(ch.properties & CBCharacteristicPropertyWriteWithoutResponse)
						? CBCharacteristicWriteWithoutResponse
						: CBCharacteristicWriteWithResponse;
				[peripheral writeValue:data forCharacteristic:ch type:writeType];
			}
		}
	});
}

- (void)forwardPacketData:(NSData *)data {
	if (!data || data.length == 0 || !_cppOwner) {
		return;
	}
	godot::PackedByteArray arr;
	arr.resize((int64_t)data.length);
	memcpy(arr.ptrw(), data.bytes, data.length);
	_cppOwner->call_deferred("_emit_packet_deferred", arr);
}

#pragma mark - Avatar photo picker

- (void)pickAvatarPhoto {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!self.cppOwner || self.photoPickerBusy) {
			return;
		}
		if (@available(iOS 14.0, *)) {
			UIViewController *presenter = nil;
			for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
				if (scene.activationState != UISceneActivationStateForegroundActive ||
					![scene isKindOfClass:UIWindowScene.class]) {
					continue;
				}
				for (UIWindow *window in ((UIWindowScene *)scene).windows) {
					if (window.isKeyWindow) {
						presenter = window.rootViewController;
						break;
					}
				}
				if (presenter) {
					break;
				}
			}
			if (!presenter) {
				// Godot exports can use an application delegate without a scene.
				for (UIWindow *window in UIApplication.sharedApplication.windows) {
					if (window.isKeyWindow) {
						presenter = window.rootViewController;
						break;
					}
				}
			}
			while (presenter.presentedViewController) {
				presenter = presenter.presentedViewController;
			}
			if (presenter && presenter.view.window) {
				PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
				configuration.filter = [PHPickerFilter imagesFilter];
				configuration.selectionLimit = 1;
				PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
				picker.delegate = self;
				self.photoPickerBusy = YES;
				[presenter presentViewController:picker animated:YES completion:nil];
				return;
			}
		}
		[self finishAvatarPhoto:nil failed:YES];
	});
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14)) {
	NSItemProvider *provider = results.firstObject.itemProvider;
	[picker dismissViewControllerAnimated:YES completion:^{
		if (!provider) {
			[self finishAvatarPhoto:nil failed:NO];
			return;
		}
		[provider loadFileRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSURL *url, NSError *error) {
			NSData *data = nil;
			CGImageSourceRef source = url && !error ? CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr) : nullptr;
			if (source) {
				NSDictionary *options = @{
					(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
					(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
					(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @1024
				};
				CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
				if (thumbnail) {
					data = UIImageJPEGRepresentation([UIImage imageWithCGImage:thumbnail], 0.9);
					CGImageRelease(thumbnail);
				}
				CFRelease(source);
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				[self finishAvatarPhoto:data failed:data.length == 0];
			});
		}];
	}];
}

- (void)finishAvatarPhoto:(NSData *)data failed:(BOOL)failed {
	self.photoPickerBusy = NO;
	if (!self.cppOwner) {
		return;
	}
	godot::PackedByteArray image;
	if (data.length > 0) {
		image.resize((int64_t)data.length);
		memcpy(image.ptrw(), data.bytes, data.length);
	}
	self.cppOwner->call_deferred("_emit_avatar_photo", image, (bool)failed);
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
	if (central.state == CBManagerStatePoweredOn && _isStarted) {
		CBUUID *serviceUUID = [CBUUID UUIDWithString:kPocketPartyServiceUUID];
		[central scanForPeripheralsWithServices:@[serviceUUID]
										options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
	}
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
	 advertisementData:(NSDictionary<NSString *, id> *)advertisementData
				  RSSI:(NSNumber *)RSSI {
	NSUUID *uuid = peripheral.identifier;
	if (!_discoveredPeripherals[uuid]) {
		_discoveredPeripherals[uuid] = peripheral;
		peripheral.delegate = self;

		NSString *name = peripheral.name ?: @"PocketParty";
		int64_t peerHash = (int64_t)(uuid.hash & 0x7FFFFFFF);
		godot::String gName([name UTF8String]);
		if (_cppOwner) {
			_cppOwner->call_deferred("_emit_peer_deferred", peerHash, gName, (int64_t)[RSSI intValue]);
		}
		[central connectPeripheral:peripheral options:nil];
	}
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
	CBUUID *serviceUUID = [CBUUID UUIDWithString:kPocketPartyServiceUUID];
	[peripheral discoverServices:@[serviceUUID]];
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
				 error:(NSError *)error {
	NSUUID *uuid = peripheral.identifier;
	[_remoteCharacteristics removeObjectForKey:uuid];
	[_discoveredPeripherals removeObjectForKey:uuid];
	if (_isStarted && central.state == CBManagerStatePoweredOn) {
		CBUUID *serviceUUID = [CBUUID UUIDWithString:kPocketPartyServiceUUID];
		[central scanForPeripheralsWithServices:@[serviceUUID]
										options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
	}
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
	if (error) {
		return;
	}
	CBUUID *charUUID = [CBUUID UUIDWithString:kPocketPartyCharUUID];
	for (CBService *service in peripheral.services) {
		[peripheral discoverCharacteristics:@[charUUID] forService:service];
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
			 error:(NSError *)error {
	if (error) {
		return;
	}
	CBUUID *targetUUID = [CBUUID UUIDWithString:kPocketPartyCharUUID];
	for (CBCharacteristic *ch in service.characteristics) {
		if ([ch.UUID isEqual:targetUUID]) {
			_remoteCharacteristics[peripheral.identifier] = ch;
			if (ch.properties & CBCharacteristicPropertyNotify) {
				[peripheral setNotifyValue:YES forCharacteristic:ch];
			}
		}
	}
}

- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
			 error:(NSError *)error {
	if (!error && characteristic.value) {
		[self forwardPacketData:characteristic.value];
	}
}

#pragma mark - CBPeripheralManagerDelegate

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
	if (peripheral.state != CBManagerStatePoweredOn || !_isStarted) {
		return;
	}
	CBUUID *serviceUUID = [CBUUID UUIDWithString:kPocketPartyServiceUUID];
	CBUUID *charUUID = [CBUUID UUIDWithString:kPocketPartyCharUUID];

	_localCharacteristic = [[CBMutableCharacteristic alloc]
		initWithType:charUUID
		  properties:(CBCharacteristicPropertyNotify | CBCharacteristicPropertyWriteWithoutResponse | CBCharacteristicPropertyWrite)
			   value:nil
		 permissions:(CBAttributePermissionsWriteable)];

	CBMutableService *service = [[CBMutableService alloc] initWithType:serviceUUID primary:YES];
	service.characteristics = @[_localCharacteristic];
	[peripheral addService:service];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
			didAddService:(CBService *)service
					error:(NSError *)error {
	if (error) {
		return;
	}
	CBUUID *serviceUUID = [CBUUID UUIDWithString:kPocketPartyServiceUUID];
	[peripheral startAdvertising:@{
		CBAdvertisementDataServiceUUIDsKey: @[serviceUUID],
		CBAdvertisementDataLocalNameKey: @"PocketParty"
	}];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
  didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
	for (CBATTRequest *req in requests) {
		if (req.value) {
			[self forwardPacketData:req.value];
		}
		[peripheral respondToRequest:req withResult:CBATTErrorSuccess];
	}
}

@end

namespace godot {

PocketPartyBLE *PocketPartyBLE::singleton = nullptr;

PocketPartyBLE *PocketPartyBLE::get_singleton() {
	return singleton;
}

PocketPartyBLE::PocketPartyBLE() {
	singleton = this;
	PPBLEManager *mgr = [[PPBLEManager alloc] initWithOwner:this];
	ble_delegate = (__bridge_retained void *)mgr;
}

PocketPartyBLE::~PocketPartyBLE() {
	if (ble_delegate) {
		PPBLEManager *mgr = (__bridge_transfer PPBLEManager *)ble_delegate;
		mgr.cppOwner = nullptr;
		[mgr stop];
		ble_delegate = nullptr;
	}
	if (singleton == this) {
		singleton = nullptr;
	}
}

void PocketPartyBLE::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start_ble"), &PocketPartyBLE::start_ble);
	ClassDB::bind_method(D_METHOD("stop_ble"), &PocketPartyBLE::stop_ble);
	ClassDB::bind_method(D_METHOD("send_ble_packet", "packet"), &PocketPartyBLE::send_ble_packet);
	ClassDB::bind_method(D_METHOD("pick_avatar_photo"), &PocketPartyBLE::pick_avatar_photo);
	ClassDB::bind_method(D_METHOD("_emit_avatar_photo", "image", "failed"), &PocketPartyBLE::_emit_avatar_photo);
	ClassDB::bind_method(D_METHOD("_emit_packet_deferred", "packet"), &PocketPartyBLE::_emit_packet_deferred);
	ClassDB::bind_method(D_METHOD("_emit_peer_deferred", "id", "peer_name", "rssi"), &PocketPartyBLE::_emit_peer_deferred);

	ADD_SIGNAL(MethodInfo("on_ble_packet", PropertyInfo(Variant::PACKED_BYTE_ARRAY, "packet")));
	ADD_SIGNAL(MethodInfo("avatar_photo_picked",
			PropertyInfo(Variant::PACKED_BYTE_ARRAY, "image"),
			PropertyInfo(Variant::BOOL, "failed")));
	ADD_SIGNAL(MethodInfo("on_peer_found",
			PropertyInfo(Variant::INT, "id"),
			PropertyInfo(Variant::STRING, "peer_name"),
			PropertyInfo(Variant::INT, "rssi")));
}

void PocketPartyBLE::start_ble() {
	if (ble_delegate) {
		PPBLEManager *mgr = (__bridge PPBLEManager *)ble_delegate;
		[mgr start];
	}
}

void PocketPartyBLE::stop_ble() {
	if (ble_delegate) {
		PPBLEManager *mgr = (__bridge PPBLEManager *)ble_delegate;
		[mgr stop];
	}
}

void PocketPartyBLE::send_ble_packet(const PackedByteArray &p_packet) {
	if (!ble_delegate || p_packet.is_empty()) {
		return;
	}
	NSData *data = [NSData dataWithBytes:p_packet.ptr() length:(NSUInteger)p_packet.size()];
	PPBLEManager *mgr = (__bridge PPBLEManager *)ble_delegate;
	[mgr broadcastPacket:data];
}

void PocketPartyBLE::_emit_packet_deferred(const PackedByteArray &p_packet) {
	emit_signal("on_ble_packet", p_packet);
}

void PocketPartyBLE::pick_avatar_photo() {
	if (ble_delegate) {
		PPBLEManager *mgr = (__bridge PPBLEManager *)ble_delegate;
		[mgr pickAvatarPhoto];
	}
}

void PocketPartyBLE::_emit_avatar_photo(const PackedByteArray &p_image, bool p_failed) {
	emit_signal("avatar_photo_picked", p_image, p_failed);
}

void PocketPartyBLE::_emit_peer_deferred(int64_t p_id, const String &p_name, int64_t p_rssi) {
	emit_signal("on_peer_found", p_id, p_name, p_rssi);
}

} // namespace godot
