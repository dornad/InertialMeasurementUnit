package etc.patexp.imu 
{
	import etc.patexp.events.IMUEvent;
	import etc.patexp.util.MathUtil;
	import etc.patexp.util.MyEventDispatcher;
	import flash.events.IEventDispatcher;
	import flash.utils.ByteArray;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.utils.Dictionary;
	import flash.utils.Timer
	import flash.utils.getTimer;
	import flash.events.TimerEvent;
	
	/**
	 * The IMU Class represents an Inertial Measurement Unit.  
	 * An IMU measures magnetic changes, acceleration and rotational changes.
	 * 
	 * This class is part of a package that allows ActionScript 3 apps to read and 
	 * use IMU data for anything needed.
	 * 
	 * This class is a wrapper around the data captured by the IMUSocket class. 
	 * Objects that conform to this class will always attempt to smooth the incoming data, 
	 * via standard deviation and mean values.
	 * 
	 * @author Daniel Rodriguez
	 */
	public class IMU implements IEventDispatcher
	{
		/**
		* How many readings must be averaged during calibration
		* @private
		*/	
		private const NUMBER_READINGS:Number = 20; 
		/**
		 * Range in which the IMU API won't start measuring angles
		 * @private
		 */
		private const _threshold:Array = [ -4, 4]
		/**
		 * A correction number according to field tests with
		 * the IMU's and turntables at 35 RPM and 45 RPM.
		 * @private
		 */
		private const DAMPENING_FACTOR:Number =  1.72;		
		
		/**
		 * Indicates IMU id, for multiple IMU handling.
		 * @private
		 */
		private static var id:int = 0;
		
		/**
		 * A data socket for communication between the C# Server 
		 * and ActionScript 3.
		 * @private
		 */
		private var imuSocket:IMUSocket;
		/**
		 * An Event Dispatcher used to implement IEventDispatcher
		 * @private
		 */
		private var eventDispatcher:MyEventDispatcher;
		/**
		 *  Flag for knowing if the calibration been done?
		 */
		private var calibrationFlag:Boolean = true;
		
		/**
		 * When did we start calculating the angle.
		 * @private
		 */
		private var startTime:Number = 0; // ms
		/**
		 * A flag for knowing if the timer is running
		 * for calculating the angle.
		 * @private
		 */
		private var timerCounting:Boolean = false;
		
		// -- The data captured for each channel, during calibration.
		private var dataCapture_magX:Array = new Array();
		private var dataCapture_magY:Array = new Array();
		private var dataCapture_magZ:Array = new Array();
		private var dataCapture_accX:Array = new Array();
		private var dataCapture_accY:Array = new Array();
		private var dataCapture_accZ:Array = new Array();
		private var dataCapture_roll:Array = new Array();
		private var dataCapture_pitch:Array = new Array();
		private var dataCapture_yaw:Array = new Array();
		private var array_Yaw:Array = new Array();    // Yaw's used for measuring angle.
		
		// -- the data recieved from the IMU, in its raw state
		internal var _id:Number;
		internal var _count:Number;
		internal var _magX:Number;
		internal var _magY:Number;
		internal var _magZ:Number;
		internal var _accX:Number;
		internal var _accY:Number;
		internal var _accZ:Number;
		internal var _roll:Number;
		internal var _pitch:Number;
		internal var _yaw:Number;
		
		// -- The calibration factor, 
		// ie.: what is the current zero.
		internal var _calibration_magX:Number;
		internal var _calibration_magY:Number;
		internal var _calibration_magZ:Number;
		internal var _calibration_accX:Number;
		internal var _calibration_accY:Number;
		internal var _calibration_accZ:Number;
		internal var _calibration_roll:Number;
		internal var _calibration_pitch:Number;
		internal var _calibration_yaw:Number;
		
		// Angles.
		internal var _angle_yaw:Number;
		
		/**
		 * Creates a new IMU object.
		 * 
		 * @throws Error Thrown if more than two IMU objects have been created.
		 */	
		public function IMU() 
		{
			_id = IMU.id++;
			
			if ( _id >= IMUSocket.MAX_IMUS )
				throw new Error( 'Can not handle more than two IMU objects.' );
			
			eventDispatcher = new MyEventDispatcher(this);
			
			imuSocket = IMUSocket.getInstance();
			imuSocket.addEventListener( Event.CONNECT, onConnect );
			imuSocket.addEventListener( IOErrorEvent.IO_ERROR, onError );
			
			IMUSocket.register(this);
		}
		
		/**
		 * Number of readings the IMU has
		 * registered since it was paired via Bluetooth.
		 */
		public function get count():int
		{
			return _count;
		}
		
		/**
		 *  The reading in the Magnetic X axis
		 */
		public function get magX():int
		{
			return _magX;
		}

		/**
		 *  The reading in the Magnetic Y axis
		 */
		public function get magY():int
		{
			return _magY;
		}
		

		/**
		 *  The reading in the Magnetic Z axis
		 */
		public function get magZ():int
		{
			return _magZ;
		}

		/**
		 *  The acceleration in the X axis
		 */
		public function get accX():int
		{
			return _accX;
		}

		/**
		 *  The acceleration in the Y axis
		 */		
		public function get accY():int
		{
			return _accY;
		}
		
		/**
		 *  The acceleration in the Z axis
		 */		
		public function get accZ():int
		{
			return _accZ;
		}

		/**
		*  The rate of change of angle, in the roll axis.
		*/
		public function get roll():int
		{
			return _roll;
		}

		/**
		*  The rate of change of angle, in the pitch axis.
		*/
		public function get pitch():int
		{
			return _pitch;
		}
		
		/**
		*  The rate of change of angle, in the yaw axis.
		*/
		public function get yaw():int
		{
			return _yaw;
		}
		
		/**
		*  Get the latest angle in the yaw axis
		*/
		public function get angleYaw():int
		{
			
			return _angle_yaw * DAMPENING_FACTOR;
		}
		
		/**
		 * Connects the IMU to the specified host and port.
		 * 
		 * @param host The name of the host to connect to.
		 * @param port The port number to connect to.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/net/Socket.html#connect() flash.net.Socket.connect()
		 */		
		public function connect( host:String = '127.0.0.1', port:int = 0x4a54 ):void
		{
			imuSocket.connect( host, port );
		}
		
		/**
		 * Closes the connection between this IMU object and the IMUFlash server.
		 */		
		public function close():void
		{
			imuSocket.close();
		}
		
		/**
		 * Updates IMU data from the Socket.
		 * @param	pack the information, in bytes, from the IMU
		 */
		internal function update( pack:ByteArray ):void
		{
			var data:Array = parseData(pack);
			
			_count = data[0] as Number
			
			_magX = data[1] as Number
			_magY = data[2] as Number
			_magZ = data[3] as Number

			_accX = data[4] as Number
			_accY = data[5] as Number
			_accZ = data[6] as Number

			_roll = data[7] as Number
			_pitch = data[8] as Number
			_yaw = data[9] as Number
			
			calibrate();
		}
		
		/**
		 * Turns the data from its Byte form into an understandable
		 * numeric form
		 * @private
		 * @param	byteArray the information, in bytes, from the IMU
		 * @return the IMU latest reading, as an array of integers
		 */
		internal function parseData(byteArray:ByteArray):Array
		{
			var arrayChannelsIMU:Array = new Array();
			
			for (var i:int = 0; i < byteArray.length; i = i + 2 )
			{
				arrayChannelsIMU.push(new Number(byteArray[i] * 256 + byteArray[i+1]));
			}
			
			return arrayChannelsIMU;
		}
		
		/**
		 *  Prepare data for being used by the application.
		 *  This includes calibration
		 */
		internal function calibrate():void
		{
			// Start calibration procedure by capturing data.
			if (dataCapture_magX.length < NUMBER_READINGS)
			{
				// Inform that the calibration has begun, and that the IMU should not be moved.
				eventDispatcher.dispatchEventOnce(new IMUEvent(IMUEvent.CALIBRATE), "IMUEvent.Calibrate");
				
				// Capture each channel.
				dataCapture_magX.push(_magX);
				dataCapture_magY.push(_magY);
				dataCapture_magZ.push(_magZ);
				dataCapture_accX.push(_accX);
				dataCapture_accY.push(_accY);
				dataCapture_accZ.push(_accZ);
				dataCapture_roll.push(_roll);
				dataCapture_pitch.push(_pitch);
				dataCapture_yaw.push(_yaw);
			}
			else 
			{
				// Use the standart deviation to filter out unwanted
				// values
				dataCapture_magX = filterValues(dataCapture_magX);
				dataCapture_magY = filterValues(dataCapture_magY);
				dataCapture_magZ = filterValues(dataCapture_magZ);
				dataCapture_accX = filterValues(dataCapture_accX);
				dataCapture_accY = filterValues(dataCapture_accY);
				dataCapture_accZ = filterValues(dataCapture_accZ);
				dataCapture_roll = filterValues(dataCapture_roll);
				dataCapture_pitch = filterValues(dataCapture_pitch);
				dataCapture_yaw = filterValues(dataCapture_yaw);
				
				// Get the mean values of the captured data.
				var mean_magX:Number = MathUtil.avg(dataCapture_magX)
				var mean_magY:Number = MathUtil.avg(dataCapture_magY)
				var mean_magZ:Number = MathUtil.avg(dataCapture_magZ)
				var mean_accX:Number = MathUtil.avg(dataCapture_accX)
				var mean_accY:Number = MathUtil.avg(dataCapture_accY)
				var mean_accZ:Number = MathUtil.avg(dataCapture_accZ)
				var mean_roll:Number = MathUtil.avg(dataCapture_roll)
				var mean_pitch:Number = MathUtil.avg(dataCapture_pitch)
				var mean_yaw:Number = MathUtil.avg(dataCapture_yaw)
				
				// We use the mean to get the calibration values.
				// These values are used to find out the equivalent
				// values in a zero based scale.
				//
				// This only happens once, during the initial calibration
				// fase, hence we use a flag *calibrationFlag* to 
				// ensure this.
				if (calibrationFlag)
				{
					_calibration_magX = 0 - mean_magX;
					_calibration_magY = 0 - mean_magY;
					_calibration_magZ = 0 - mean_magZ;
					
					_calibration_accX = 0 - mean_accX;
					_calibration_accY = 0 - mean_accY;
					_calibration_accZ = 0 - mean_accZ;
					
					_calibration_roll = 0 -  mean_roll;
					_calibration_pitch = 0 - mean_pitch;
					_calibration_yaw = 0 -   mean_yaw;

					// At this point, we are done with the initial calibration.
					// Flash will use this values automatically.
					calibrationFlag = false;
					eventDispatcher.dispatchEvent(new IMUEvent(	IMUEvent.CALIBRATION_DONE));
				}
				
				// Apply the calibration values to the data.
				// This gives out the values in a zero based scale
				_magX += _calibration_magX;
				_magY += _calibration_magY;
				_magZ += _calibration_magZ;
				
				_accX += _calibration_accX;
				_accY += _calibration_accY;
				_accZ += _calibration_accZ;
				
				_roll += _calibration_roll;
				_pitch += _calibration_pitch;
				_yaw += _calibration_yaw;	
				
				// Now that the data has been calibrated, it is 
				// valid for calculating angles.
				getAngles();
				
				// The data is ready to be used by our application.  We call the UPDATE
				// event for this.
				eventDispatcher.dispatchEvent(new IMUEvent(	IMUEvent.UPDATE));
				
				// We empty the arrays (recreate them is faster, hence they're re-instantiated)
				// so we can have a new set of data to be averaged.
				dataCapture_magX = new Array();
				dataCapture_magY = new Array();
				dataCapture_magZ = new Array();
				dataCapture_accX = new Array();
				dataCapture_accY = new Array();
				dataCapture_accZ = new Array();
				dataCapture_roll = new Array();
				dataCapture_pitch = new Array();
				dataCapture_yaw = new Array();
			}
			
		}
		
		/**
		 * We filter unwanted values, using standard deviation 
		 * and mean values.
		 * 
		 * @param	data the group of data we want to examine
		 * @return the data sans the unwanted values. 
		 * @private
		 */
		private function filterValues(data:Array):Array
		{
			var filteredData:Array = new Array();
			var s:Number = MathUtil.getStandardDeviation(data);	
			var m:Number = MathUtil.avg(data);
			var numElementsFilteredData:Number = 0;
			
			for each(var value:Number in data)
			{
				if (MathUtil.inRange(value, [m - s, m + s]))
				{
					filteredData.push(value);
				}
				else
				{
					numElementsFilteredData ++;
				}
			}
			return filteredData;
		}
		
		
		/**
		 * Calculate the angles.
		 * @private
		 */
		private function getAngles():void
		{
			if ( MathUtil.inRange(yaw, _threshold ))
			{
				// get the total time and angle
				if (timerCounting)
				{
					timerCounting = false;
					var elapsedTime:Number = (getTimer() - startTime) * 0.001;
					var avgYaw:Number = MathUtil.avg(array_Yaw);
					_angle_yaw = avgYaw * elapsedTime; 
					
					array_Yaw = new Array();
					trace("yaw,elapsedTime,angleYaw = " + avgYaw + " deg/s, " + elapsedTime + " s, " + angleYaw+" deg");
				}
				else
				{
					// the timer is not running, therefore the angle is cero.
					_angle_yaw = 0; 
				}
			}
			else
			{
				// start the timer and begin capturing data
				if (timerCounting)	array_Yaw.push(yaw);
				else
				{
					startTime = getTimer();
					timerCounting = true;
				}
			}
		}
		
		/**
		 * String representation of the class
		 * 
		 * @return a string representation of the IMU's data.
		 */
		public function toString():String
		{
			var str:String = "";
			str = str.concat("_magX[" + _magX + "]\n");
			str = str.concat("_magY[" + _magY + "]\n");
			str = str.concat("_magZ[" + _magZ + "]\n");
			
			str = str.concat("_accX[" + _accX + "]\n");
			str = str.concat("_accY[" + _accY + "]\n");
			str = str.concat("_accZ[" + _accZ + "]\n");
			
			str = str.concat("_roll[" + _roll + "]\n");
			str = str.concat("_pitch[" + _pitch + "]\n");
			str = str.concat("_yaw[" + _yaw + "]\n");
			
			return str;
		}
		
		/**
		 * Dispatched when the IMU is successfully connected to the IMU C# Server.
		 * 
		 * @eventType flash.events.Event.CONNECT
	 	 */	
		private function onConnect( event:Event ):void
		{
			eventDispatcher.dispatchEvent( event );
		}
		
		/**
		 * Dispatched when the IMU is disconnected connected to the IMU C# Server.
		 * 
		 * @eventType flash.events.Event.CLOSE
	 	 */	
		private function onError( event:Event ):void
		{
			eventDispatcher.dispatchEvent( event );
		}
		
		
		//-----------------------------------------------------------------------------------
		// IEventDispatcher
		//-----------------------------------------------------------------------------------
		 
		/**
		 * Registers an event listener object with a IMU object so that the listener receives notification of an event.
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
			eventDispatcher.addEventListener( type, listener, useCapture, priority, useWeakReference );
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
			return eventDispatcher.dispatchEvent( event );
		}
		
		/**
		 * Checks whether the IMU object has any listeners registered for a specific type of event.
		 * 
		 * @param type The type of event.
		 * @return A value of <code>true</code> if a listener of the specified type is registered; <code>false</code> otherwise.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#hasEventListener() flash.events.IEventDispatcher.hasEventListener()
		 */		
		public function hasEventListener( type:String ):Boolean
		{
			return eventDispatcher.hasEventListener( type );
		}
		
		/**
		 * Removes a listener from the IMU object.
		 * 
		 * @param type The type of event.
		 * @param listener The listener object to remove.
		 * @param useCapture Specifies whether the listener was registered for the capture phase or the target and bubbling phases.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#removeEventListener() flash.events.IEventDispatcher.removeEventListener()
		 */		
		public function removeEventListener( type:String, listener:Function, useCapture:Boolean = false ):void
		{
			eventDispatcher.removeEventListener( type, listener, useCapture );
		}
		
		/**
		 * Checks whether an event listener is registered with this IMU object or any of its ancestors for the specified event type.
		 * 
		 * @param type The type of event.
		 * @return A value of <code>true</code> if a listener of the specified type will be triggered; <code>false</code> otherwise.
		 * 
		 * @see http://livedocs.adobe.com/flex/2/langref/flash/events/IEventDispatcher.html#willTrigger() flash.events.IEventDispatcher.willTrigger()
		 */	
		public function willTrigger( type:String ):Boolean
		{
			return eventDispatcher.willTrigger( type );
		}

		
		
	}
	
}