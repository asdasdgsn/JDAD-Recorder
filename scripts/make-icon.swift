import AppKit
let size = NSSize(width:1024,height:1024)
let image = NSImage(size:size)
image.lockFocus()
NSColor(calibratedRed:0.065,green:0.073,blue:0.086,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:22,y:22,width:980,height:980),xRadius:210,yRadius:210).fill()
let mint = NSColor(calibratedRed:0.65,green:0.91,blue:0.72,alpha:1)
mint.setStroke()
let ring = NSBezierPath(ovalIn:NSRect(x:215,y:215,width:594,height:594)); ring.lineWidth = 44; ring.stroke()
mint.setFill()
NSBezierPath(ovalIn:NSRect(x:389,y:389,width:246,height:246)).fill()
image.unlockFocus()
let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
