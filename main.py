import serial
import time


def main():
    ser = serial.Serial()
    ser.port = 'COM4'
    ser.baudrate= 9600
    ser.parity=serial.PARITY_NONE
    ser.stopbits=serial.STOPBITS_ONE
    ser.bytesize=serial.EIGHTBITS
    ser.timeout= 1.5
    ser.open()
    while True:
        data = ser.read(4).hex()
        print("HEX Data :\t " + data)    
        temp(data[0:4])
        hum(data[4:8])
    ser.close()

def temp(hex):
    TEMP = (175.72 * int(hex, 16))/65536 - 46.85
    print("Temperature :\t" + str(TEMP)[0:5] + " °C")
    return 0;

def hum(hex):
    HUM = (125 * int(hex, 16))/65536 - 6
    print("Humidity :\t" + "%" + str(HUM)[0:5] + "\n")
    return 0;

if __name__ == "__main__":
    main()