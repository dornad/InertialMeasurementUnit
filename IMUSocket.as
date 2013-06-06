package etc.patexp.imu 
{
	import flash.events.IEventDispatcher;
	import flash.net.Socket;
	import Error;
	import flash.events.Event;
	import flash.events.ProgressEvent;
	import flash.utils.ByteArray;
	
	/**
	 * The IMU Class represents an Inertial Measurement Unit.  
	 * An IMU measures magnetic changes, acceleration and rotational changes.
	 * 
	 * This class is part of a package that allows ActionScript 3 apps to read and 
	 * use IMU data for anything needed.
	 * 
	 * This class uses AS3's flash.net.socket API to read input from a C# server.  The data is
	 * checked for validity.  If a raw package is valid an event is dispatched so this data
	 * can be used.
	 * 
	 * @author Daniel Rodriguez
	 */
	internal final class IMUSocket implements IEventDispatcher
	{
		/**
		 * The maximum number of IMU tha can be connected
		 * @default 2
		 */
		public static const MAX_IMUS:int = 2;
		/**
		 * The starting position of the byte data array
		 */
		private static const BYTE_ARRAY_OFFSET:int = 0;
		/**
		 * The ending position of the byte data array
		 */
		private static const BYTE_ARRAY_LENGTH:int = 40;
		/**
		 * An instance used to force singleton behaviour.
		 */
		private static var instance:IMUSocket;
		/**
		 *  A flag used for singleton behaviour.
		 *  @default false
		 */
		private static var initializing:Boolean = false;
		/**
		 * A Flash data socket.
		 */
		private var socket:Socket;
		/**
		 *  Incomming data storage from the data socket
		 */
		private var buffer:ByteArray;
		/**
		 * The full data reading from IMU # 1
		 */
		private var rawPackageIMU1:ByteArray;
		/**
		 * The full data reading from IMU # 2
		 */
		private var rawPackageIMU2:ByteArray;
		/**
		 * The IMU objects that use this class.
		 */
		private var imus:Array;
		
		/**
		 * Creates a new IMUSocket object.
		 */
		public function IMUSocket() 
		{
			if ( !initializing )
				throw new Error( 'This is a singleton. Use IMUSocket.getInstance().' );
			
			imus = new Array();
			socket = new Socket;
			buffer = new ByteArray;
			rawPackageIMU1 = new ByteArray();
			rawPackageIMU2 = new ByteArray();
			
			socket.addEventListener( ProgressEvent.SOCKET_DATA, onSocketData );
		}
		
		/**
		 * Attaches an imu object with this instance, so it can 
		 * recieve data.
		 * 
		 * @param	imu an imu object
		 */
		public static function register( imu:IMU ):void
		{
			getInstance().imus[imu._id] = imu;
		}
		
		/**
		 * Get a singleton instance of this class
		 * @return the instance of this class.
		 */
		public static function getInstance():IMUSocket
		{
			if ( instance == null )
			{
				initializing = true;
				instance = new IMUSocket();
				initializing = false;
			}
			
			return instance;
		}
		
		/**
		 * Connects to the IMU C# Server
		 * @param	host C# server address.  Defaults to 127.0.0.1, the localhost
		 * @param	port C# server port.  Defaults to 0x4a54
		 */
		public function connect( host:String = '127.0.0.1', port:uint = 0x4a54 ):void
		{
			if ( !socket.connected )
				socket.connect( host, port );
			else
				dispatchEvent( new Event( Event.CONNECT ) );
		}
		
		/**
		 * Recieve data from the socket and passes it to the 
		 * imu object upon successful read.
		 * 
		 * @param	event the event that triggered this method call.
		 */
		private function onSocketData( event:ProgressEvent ):void
		{
			while ( socket.bytesAvailable > 0 )
			{
				buffer.writeByte( socket.readByte() );
				
				if ( buffer.position == BYTE_ARRAY_LENGTH )
				{
					rawPackageIMU1.writeBytes(buffer, 0, 20);
					rawPackageIMU2.writeBytes(buffer, 20, 20);
					
					buffer.position = rawPackageIMU1.position = rawPackageIMU2.position = BYTE_ARRAY_OFFSET;
					
			     	try
			     	{
				     	( imus[ 0 ] as IMU ).update( rawPackageIMU1 );
						( imus[ 1 ] as IMU ).update( rawPackageIMU2 );
				    }
				    catch ( error:Error ) {}
				}
			}
		}
	
		/**
		 * Closes the connection between Flash and the IMU C# Server.
		 */	
		public function close():void
		{
			socket.close();
		}
		
		/**
		 * Registers an event listener object with a IMUSocket object so that the listener receives notification of an event.
		 * 
		 * @param type The type of event.
		 * @param listener The listener function that processes the event.
		 * @param useCapture Determines whether the listener works in the capture phase or the target and bubbling phases.
		 * @param priority The priority level of the event listener.
		 * @param useWeakReference Determines whether the reference to the listener is strong or weak.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#addEventListener() flash.events.IEventDispatcher.addEventListener()
		 */		
		public function addEventListener( type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false ):void 
		{
			socket.addEventListener( type, listener, useCapture, priority, useWeakReference );
		}

		/**
		 * Dispatches an event into the event flow.
		 * 
		 * @param event The Event object dispatched into the event flow.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#dispatchEvent() flash.events.IEventDispatcher.dispatchEvent()
		 */
		public function dispatchEvent( event:Event ):Boolean
		{
			return socket.dispatchEvent( event );
		}
		
		/**
		 * Checks whether the IMUSocket object has any listeners registered for a specific type of event.
		 * 
		 * @param type The type of event.
		 * @return A value of <code>true</code> if a listener of the specified type is registered; <code>false</code> otherwise.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#hasEventListener() flash.events.IEventDispatcher.hasEventListener()
		 */	
		public function hasEventListener( type:String ):Boolean
		{
			return socket.hasEventListener( type );
		}
		
		/**
		 * Removes a listener from the IMUSocket object.
		 * 
		 * @param type The type of event.
		 * @param listener The listener object to remove.
		 * @param useCapture Specifies whether the listener was registered for the capture phase or the target and bubbling phases.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#removeEventListener() flash.events.IEventDispatcher.removeEventListener()
		 */	
		public function removeEventListener( type:String, listener:Function, useCapture:Boolean = false ):void
		{
			socket.removeEventListener( type, listener, useCapture );
		}
		
		/**
		 * Checks whether an event listener is registered with this IMUSocket object or any of its ancestors for the specified event type.
		 * 
		 * @param type The type of event.
		 * @return A value of <code>true</code> if a listener of the specified type will be triggered; <code>false</code> otherwise.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#willTrigger() flash.events.IEventDispatcher.willTrigger()
		 */	
		public function willTrigger( type:String ):Boolean
		{
			return socket.willTrigger( type );
		}
	}
}