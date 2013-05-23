package  
{
	import flash.desktop.NativeApplication;
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.NativeWindow;
	import flash.display.NativeWindowDisplayState;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.*;
	import flash.filesystem.File;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.system.Capabilities;
	import flash.text.*;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	import flash.utils.setTimeout;


	[SWF(frameRate="60", backgroundColor="#ffffff")]
	public class NativeProcessTest extends Sprite 
	{
		private static const PROCESS_ENDIANNESS:String = Endian.LITTLE_ENDIAN; // .NET process uses little-endian
		private static const PROCESS_PATH:String = "ScreenCapturer.exe";
		private static const PROCESS_GETIMAGECOMMAND:String = "GET";
		private static const PROCESS_STARTCODE:uint = 9999999;
		private static const PROCESS_ENDCODE:uint = 6666666;
		
		private var _process:NativeProcess;		
		private var _imageData:ByteArray;

		private var _requestedWidth:int = 640;
		private var _requestedHeight:int = 480;
		private var _requestedOffsetX:int = 100;
		private var _requestedOffsetY:int = 100;

		private var _expectedImageLength:Number;
		private var _imageWidth:int;
		private var _imageHeight:int;
		private var _isReceivingData:Boolean;
		private var _startReceiveTimestamp:Number;
		private var _startRequestTimestamp:Number;

		private var _mouseDownMousePos:Point; 
		private var _mouseDownOffsetPos:Point; 
		private var _timestamps:Array = [];
		
		private var _image:Bitmap;
		private var _tf1:TextField;
		private var _tf2:TextField;
		
		
		public function NativeProcessTest() 
		{
			this.stage.frameRate = 30;
			this.stage.align = StageAlign.TOP_LEFT;
			this.stage.scaleMode = StageScaleMode.NO_SCALE;
			this.stage.nativeWindow.x = Capabilities.screenResolutionX - _requestedWidth - 100; 
			this.stage.nativeWindow.y = 50; 
			this.stage.nativeWindow.visible = true;

			initUi();
			
			var success:Boolean = initProcess();
			if (! success) return;
			
			setTimeout(requestImage, 333, _requestedWidth, _requestedHeight, _requestedOffsetX, _requestedOffsetY); // .. for good measure
		}
		
		private function initUi():void
		{
			var s:Sprite = new Sprite();
			s.buttonMode = true;
			this.addChild(s);
			_image = new Bitmap();
			s.addChild(_image);

			_tf1 = new TextField();
			_tf1.width = 640;
			_tf1.selectable = false;
			_tf1.defaultTextFormat = new TextFormat("_sans", 16, 0xffffff, true);
			_tf1.htmlText = "SELECT IMAGE DIMENSIONS:  <u><a href='event:640_480'>640x480</a></u>  <u><a href='event:800_600'>800x600</a></u>  <u><a href='event:1024_768'>1024x768</a></u>  <u><a href='event:1280_1024'>1280x1024</a></u>";
			_tf1.addEventListener(TextEvent.LINK, onTextLink);
			this.addChild(_tf1);
			
			_tf2 = new TextField();
			_tf2.autoSize = TextFieldAutoSize.LEFT;
			_tf2.defaultTextFormat = new TextFormat("_sans", 16, 0xffffff, true);
			this.addChild(_tf2);
			
			_tf1.height = _tf2.height = 25;
			_tf1.background = _tf2.background = true;
			_tf1.backgroundColor = _tf2.backgroundColor = 0x00;
			
			this.stage.nativeWindow.addEventListener(NativeWindowDisplayStateEvent.DISPLAY_STATE_CHANGE, onDisplayStateChange);
			this.stage.addEventListener(Event.MOUSE_LEAVE, onLeave);
			this.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
		}
		
		public function initProcess():Boolean
		{
			if (Capabilities.os.toLowerCase().indexOf("win") == -1) {
				_tf1.htmlText = "<font size='18'>Sorry, Windows only.</font>";
				return false;
			}
			
			if (! NativeProcess.isSupported) {
				_tf1.htmlText = "<font size='18'>NativeProcess not supported.</font>";
				return false;
			}
			
			var np:Class = NativeProcess;
			
			var file:File = File.applicationDirectory;
			file = file.resolvePath(PROCESS_PATH);

			var nativeProcessStartupInfo:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			
			try {
				nativeProcessStartupInfo.executable = file;
			}
			catch (e:Error) {
				_tf1.htmlText = "<font size='18'>Couldn't launch executable:<br/>" + e.message + "</font>";
				return false;
			}

			_process = new NativeProcess();
			_process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, onStandardOutput);
			_process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onStandardError);
			_process.addEventListener(ProgressEvent.STANDARD_INPUT_PROGRESS, onStandardInputProgress);
			_process.standardOutput.endian = PROCESS_ENDIANNESS;
			_process.start(nativeProcessStartupInfo);
			NativeApplication.nativeApplication.addEventListener(Event.EXITING, onAppExiting);
			_process.running
			
			return true;
		}
		
		//
		
		private function onDisplayStateChange($e:NativeWindowDisplayStateEvent):void
		{
			if ($e.afterDisplayState == NativeWindowDisplayState.NORMAL) 
				requestImage(_requestedWidth, _requestedHeight, _requestedOffsetX, _requestedOffsetY);
		}
		
		private function onLeave(e:*):void
		{
			_tf1.visible = false;
			this.stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		}
		private function onMouseMove(e:*):void
		{
			_tf1.visible = true;
			this.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
		}
		
		private function onTextLink($e:TextEvent):void
		{
			trace("onTextLink");
			var a:Array = $e.text.split("_");
			_requestedWidth = parseInt(a[0]);
			_requestedHeight = parseInt(a[1]);
		}
		
		private function onDragStart(e:*):void
		{
			_mouseDownMousePos = new Point(this.mouseX, this.mouseY);
			_mouseDownOffsetPos = new Point(_requestedOffsetX, _requestedOffsetY);
			
			this.addEventListener(Event.ENTER_FRAME, onDragging);
			this.stage.addEventListener(MouseEvent.MOUSE_UP, onDragEnd);
			this.stage.addEventListener(Event.MOUSE_LEAVE, onDragEnd);
		}
		
		private function onDragging(e:*):void
		{
			var dx:int = this.mouseX - _mouseDownMousePos.x;
			var dy:int = this.mouseY - _mouseDownMousePos.y;
			_requestedOffsetX = _mouseDownOffsetPos.x - dx;
			_requestedOffsetY = _mouseDownOffsetPos.y - dy;
		}
		
		private function onDragEnd(e:*):void
		{
			this.removeEventListener(Event.ENTER_FRAME, onDragging);
			this.stage.removeEventListener(MouseEvent.MOUSE_UP, onDragEnd);
			this.stage.removeEventListener(Event.MOUSE_LEAVE, onDragEnd);
		}
		
		private function onStandardInputProgress(event:ProgressEvent):void
		{
			// Do nothing
			// _process.closeInput();
		}

		private function onStandardOutput(event:ProgressEvent):void
		{
			processStandardOut();
		}
		
		public function onStandardError(event:ProgressEvent):void
		{
			trace("Error: " + _process.standardError.readUTFBytes(_process.standardError.bytesAvailable));
		}
		
		private function onAppExiting(e:*):void
		{
			if (_process && _process.running) 
			{ 
				_process.removeEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, onStandardOutput);
				_process.removeEventListener(ProgressEvent.STANDARD_ERROR_DATA, onStandardError);
				_process.removeEventListener(ProgressEvent.STANDARD_INPUT_PROGRESS, onStandardInputProgress);
				_process.exit(true);
			}
		}
		
		//
		
		private function requestImage($width:int, $height:int, $offsetX:int, $offsetY:int):Boolean
		{
			if (! _process || ! _process.running) return false;
	
			if (_isReceivingData) {
				trace('Skipping - already trying to receive an image');
				return false;
			}
			
			benchmarkCalc();

			// bounds check
			_requestedOffsetX = Math.min(_requestedOffsetX, Capabilities.screenResolutionX - _requestedWidth);
			_requestedOffsetY = Math.min(_requestedOffsetY, Capabilities.screenResolutionY - _requestedHeight);
			_requestedOffsetX = Math.max(_requestedOffsetX, 0);
			_requestedOffsetY = Math.max(_requestedOffsetY, 0);
			
			var s:String = PROCESS_GETIMAGECOMMAND + " " + 
				_requestedWidth.toString() + " " + 
				_requestedHeight.toString() + " " + 
				_requestedOffsetX.toString() + " " + 
				_requestedOffsetY.toString() + "\n";
			
			_process.standardInput.writeUTFBytes(s);

			_startRequestTimestamp = new Date().getTime();			
			
			_isReceivingData = true;
			
			return true;
		}
		
		private function processStandardOut():void
		{
			// Check first 4 bytes for start code
			var first4:int = _process.standardOutput.readUnsignedInt(); 
			if (first4 == PROCESS_STARTCODE)
			{
				// error check
				if (_process.standardOutput.bytesAvailable < 8) {
					trace('Header appears to be split between packets. Ignoring rather than writing extra logic.');
					return;
				}
				
				_startReceiveTimestamp = new Date().getTime();

				// trace('Time waiting for response: ', _startReceiveTimestamp - _startRequestTimestamp);
				
				_imageWidth = _process.standardOutput.readInt();
				_imageHeight = _process.standardOutput.readInt();
				
				_expectedImageLength = _imageWidth * _imageHeight * 4;
				
				_imageData = new ByteArray();
				_imageData.endian = Endian.LITTLE_ENDIAN;
				
				if (_process.standardOutput.bytesAvailable == 0) return; // (expected behavior)
			} 
			else // ... that first longword is part of the real image data, so write it to our ByteArray
			{
				_imageData.writeInt(first4);
			}

			// Write the remainder of the stdout data to the ByteArray
			_process.standardOutput.readBytes(_imageData, _imageData.length);

			// Check last 4 bytes for termination code
			_imageData.position = _imageData.length - 4;
			var last4:int = _imageData.readUnsignedInt();
			
			if (last4 == PROCESS_ENDCODE) 
			{
				_imageData.length = _imageData.length - 4; // .. remove endcode from bytearray
				_isReceivingData = false;
				
				if (_imageData.length != _expectedImageLength) trace("Image not of expected length: ", _imageData.length, "versus", _expectedImageLength);
				
				// trace('Time taken to transfer data: ', new Date().getTime() - _startReceiveTimestamp);
				
				drawImage(_imageData);
			}
		} 

		private function drawImage($b:ByteArray):void
		{
			// Make new bitmapdata if necessary
			if (! _image.bitmapData || _image.bitmapData.width != _imageWidth || _image.bitmapData.height != _imageHeight) {
				if (_image.bitmapData) _image.bitmapData.dispose();
				_image.bitmapData = new BitmapData(_imageWidth,_imageHeight,false);
			}

			// Apply image
			$b.position = 0;
			_image.bitmapData.setPixels(new Rectangle(0,0,_imageWidth,_imageHeight), $b);
			
			// *** This is where you might use or manipulate the BitmapData to have the app do something actually useful...

			// If window is minimized, return
			if (this.stage.nativeWindow.displayState == NativeWindowDisplayState.MINIMIZED) return;

			// Resize window if necessary 
			var px:Number = this.stage.nativeWindow.width - this.stage.stageWidth;
			var py:Number = this.stage.nativeWindow.height - this.stage.stageHeight;

			if (this.stage.nativeWindow.width != _imageWidth + px) {
				this.stage.nativeWindow.width = _imageWidth + px;
				_tf1.width = _imageWidth;
				_tf2.x = _imageWidth - 58;
			}
			if (this.stage.nativeWindow.height != _imageHeight + py) {
				this.stage.nativeWindow.height = _imageHeight + py;
			}

			// Immediately request new image
			requestImage(_requestedWidth, _requestedHeight, _requestedOffsetX, _requestedOffsetY);
		}
		
		private function benchmarkCalc():void
		{
			var now:Number = new Date().getTime();
			_timestamps.push(now);
			
			if (_timestamps.length > 10) {
				var msPerFrame:Number = (now - _timestamps.shift()) / 10;
				var framesPerSecond:Number = 1000 / msPerFrame;
				_tf2.text = Math.round(framesPerSecond).toString() + " FPS";
			}
		}
	}	
}