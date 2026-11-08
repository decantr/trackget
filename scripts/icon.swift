import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let image = NSImage(contentsOfFile: arguments[1]) else {
	print("usage: icon.swift <icon.svg> <out.iconset>")
	exit(1)
}
let out_dir = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: out_dir, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
	for scale in [1, 2] {
		let pixels = size * scale
		let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		)!
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
		image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
		NSGraphicsContext.restoreGraphicsState()
		let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
		try bitmap.representation(using: .png, properties: [:])!.write(to: out_dir.appendingPathComponent(name))
	}
}
