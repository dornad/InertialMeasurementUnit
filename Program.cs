using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Net;
using System.Net.Sockets;
using System.IO.Ports;
using System.IO;
using System.Windows.Forms;
using log4net;
using Utility.LoggingService;


namespace etc.patexp
{
    /// <summary>
    /// An Console application that handles communication between
    /// Flash and the 6DoF v4 IMU.
    /// 
    /// Uses Sockets for communcation between .NET and AS3.
    /// 
    /// http://www.sparkfun.com/datasheets/Sensors/DataSheet-6DOF-v4-Rev1.pdf
    /// </summary>
    class IMUFlashServer
    {
        #region Members

            /// <summary>
            /// Connection to the IMU # 1
            /// </summary>
            private SerialPort port_imu_1;

            /// <summary>
            /// Connection to the IMU # 2
            /// </summary>
            private SerialPort port_imu_2;

            /// <summary>
            /// Socket listener for incomming connection from Clients.
            /// </summary>
            public Socket m_socListener;

            /// <summary>
            /// Socket for sending data to Flash
            /// </summary>
            public Socket m_socWorker;

            /// <summary>
            /// An event handler, defined as an object
            /// to allow detachment and re-atachment of
            /// Serial Data Recieved events.
            /// </summary>
            private SerialDataReceivedEventHandler eventHandler;

            /// <summary>
            /// Flag for Attempting Socket Connection
            /// </summary>
            private Boolean flagAttemptSocketConnection = true;

            /// <summary>
            /// Flag that tells if there's a Socket Connection
            /// to Flash.
            /// </summary>
            private Boolean flagClientConnected = false;

            /// <summary>
            /// A flag for making sure that a message is printed only 
            /// once.
            /// </summary>
            private Boolean flagOneTimeMsg = true;

            /// <summary>
            /// A flag for knowing if the data from both IMU's is ready
            /// to be sent to Flash.
            /// </summary>
            private bool[] dataReady = {false,false};

            /// <summary>
            /// Data from IMU 1
            /// </summary>
            private byte[] data_imu_1 = new byte[20];

            /// <summary>
            /// Data from IMU 2
            /// </summary>
            private byte[] data_imu_2 = new byte[20];

        #endregion

        #region Constructors

            /// <summary>
            /// main
            /// </summary>
            /// <param name="args">program arguments</param>
            static void Main(string[] args)
            {
                CLogger.WriteLog(ELogLevel.INFO, "ImuFlash Server v.0.2");
                CLogger.WriteLog(ELogLevel.INFO, "Searching for IMU...");

                IMUFlashServer p = new IMUFlashServer();
                p.searchForIMU();
            }

        #endregion

        #region methods

            /// <summary>
            /// Searches for IMU
            /// </summary>
            public void searchForIMU()
            {
                CLogger.WriteLog(ELogLevel.DEBUG, "Opening Serial Port connection to COM7");
                CLogger.WriteLog(ELogLevel.DEBUG, "Opening Serial Port connection to COM8");

                // Open a new Serial Port to IMU # 1
                port_imu_1 = new SerialPort("COM7", 115200, Parity.None, 8, StopBits.One);
                // Open a new Serial Port to IMU # 2
                port_imu_2 = new SerialPort("COM8", 115200, Parity.None, 8, StopBits.One);
                
                // Define the Data Recieved event handler
                eventHandler = new SerialDataReceivedEventHandler(portDataReceived);
                
                // Register the event handlers
                port_imu_1.DataReceived += eventHandler;
                port_imu_2.DataReceived += eventHandler;

                try
                {
                    // Open the ports.
                    port_imu_1.Open();
                    port_imu_2.Open();

                    // Set the IMUs in 1.5G (see IMU documentation at the Sparkplug website for more info)
                    port_imu_1.Write("%");
                    port_imu_2.Write("%");

                    // Set the frequency to 50 Hz (see IMU documentation at the Sparkplug website for more info)
                    port_imu_1.Write(")");
                    port_imu_2.Write(")");

                    // Sets the IMU in binary mode with 
                    // all channels active. (see IMU documentation at the Sparkplug website for more info)
                    port_imu_1.Write("#");
                    port_imu_2.Write("#");
                }
                catch (IOException ioe)
                {
                    CLogger.WriteLog(ELogLevel.WARN, ioe.Message);
                }

                // Wait for data available to be sent.
                while (true)
                {
                    
                    if (dataReady[0] == true && dataReady[1] == true)
                    {
                        CLogger.WriteLog(ELogLevel.DEBUG, "Sending data to Flash");
                        byte[] data_imus = new byte[40];
                        dataReady[0] = dataReady[1] = false;

                        for (int i = 0; i < 40; i++)
                        {
                            if (i < 20)
                            {
                                data_imus[i] = data_imu_1[i];
                            }
                            else
                            {
                                data_imus[i] = data_imu_2[i-20];
                            }
                        }
                        sndMsj(data_imus);
                    }
                }

                // Keep this thread running. 
                // Application.Run();
            }

            /// <summary>
            /// Start the socket and listens
            /// for incomming connections from clients.
            /// </summary>
            public void connect()
            {
                try
                {
                    // Create the socket
                    m_socListener = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                    
                    // Get the local address and the port.
                    IPEndPoint ipLocal = new IPEndPoint(IPAddress.Any, 19028);
                    
                    // Bind the local addr to the socket.
                    m_socListener.Bind(ipLocal);
                    
                    // Start listening.
                    m_socListener.Listen(4);
                    
                    // Add an event listener for client connection
                    m_socListener.BeginAccept(new AsyncCallback(onClientConnect), null);
                }
                catch (SocketException se)
                {
                    CLogger.WriteLog(ELogLevel.ERROR, se.Message);
                }
            }

            /// <summary>
            /// Recieve the event and handles the data from the connection.
            /// </summary>
            /// <param name="sender"></param>
            /// <param name="eventArgs"></param>
            private void portDataReceived(object sender,SerialDataReceivedEventArgs eventArgs)
            {
                try
                {
                    if (sender == port_imu_1)
                    {
                        const int imu_id = 0;
                        handleData(port_imu_1,imu_id);
                    }
                    else if (sender == port_imu_2)
                    {
                        const int imu_id = 1;
                        handleData(port_imu_2,imu_id);
                    }
                }
                catch (SocketException se)
                {
                    CLogger.WriteLog(ELogLevel.ERROR, se.Message);
                }
            }

            /// <summary>
            /// Prepare the data for being sent to Flash.
            /// </summary>
            /// <param name="port">the connection to an IMU</param>
            private void handleData(SerialPort port,int imu_id)
            {
                try
                {
                    if (flagOneTimeMsg)
                    {
                        CLogger.WriteLog(ELogLevel.INFO, "Connection established with IMUs");
                        flagOneTimeMsg = false;
                    }

                    /*
                     *  Attempt to connect via Socket 
                     *  to Flash.
                     *  
                     *  flagAttemptSocketConnection is used
                     *  to ensure that this only happens once
                     */
                    if (flagAttemptSocketConnection)
                    {
                        CLogger.WriteLog(ELogLevel.INFO, "Listening for Client App thru Socket");
                        this.connect();
                        flagAttemptSocketConnection = false;
                    }

                    /* 
                     * This line is very important.  What it does is that it removes
                     * the dataRecieved event handler of the serial port.
                     * 
                     * this is to make sure that we only process one raw reading.
                     */
                    port.DataReceived -= this.eventHandler;     // Remove the dataRecieved event handler.

                    // Search for the header 'A' (ASCII 65)
                    while (port.ReadChar() != 65 ) {}

                    // Get the 20 Active channels and
                    // place them inside the array
                    for (int i = 0; i < 20; i++)
                    {
                        int data = port.ReadByte();
                        if (imu_id == 0)
                        {
                            data_imu_1[i] = (byte)data;
                        }
                        else
                        {
                            data_imu_2[i] = (byte)data;
                        }
                    }
                   

                    // If the channels are followed by a 
                    // Z (ASCII 90)...
                    if (port.ReadChar() == 90 && flagClientConnected)
                    {
                        // We got a valid data input from the IMU
                        // proceed to send the data via
                        // Socket.
                        dataReady[imu_id] = true;
                    }
                    // Adds again the data recieved event handler.
                    port.DataReceived += this.eventHandler;
                }
                catch (SocketException se)
                {
                    CLogger.WriteLog(ELogLevel.ERROR, se.Message);
                }
            }
            
            /// <summary>
            /// Handles a client connection via Socket.
            /// 
            /// Starts the Serial Port connection.
            /// </summary>
            /// <param name="asyn"></param>
            public void onClientConnect(IAsyncResult asyn)
            {
                try
                {
                    CLogger.WriteLog(ELogLevel.INFO, "Client connected.");

                    // Dunno what is this for...
                    m_socWorker = m_socListener.EndAccept(asyn);
                     
                    // Allow comunication to Flash.
                    // See portDataRecieved()
                    flagClientConnected = true;
                }
                catch (ObjectDisposedException)
                {
                    CLogger.WriteLog(ELogLevel.WARN, "\n OnClientConnection: Socket has been closed\n");
                }
                catch (SocketException se)
                {
                    CLogger.WriteLog(ELogLevel.ERROR, se.Message);
                }
            }

            /// <summary>
            /// Send a message via socket to Flash.
            /// </summary>
            /// <param name="byData"></param>
            private void sndMsj(byte[] byData)
            {
                try
                {
                    m_socWorker.Send(byData);
                }
                catch (SocketException se)
                {
                    CLogger.WriteLog(ELogLevel.ERROR, se.Message);

                    m_socWorker.Close();
                    m_socListener.Close();

                    flagAttemptSocketConnection = true;
                    flagClientConnected = false;
                }
            }

        #endregion

    }
}


