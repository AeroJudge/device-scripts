# AeroJudge Device App Bootstrap Script Install

Legacy hardware instructions. The legacy setup implementation is maintained in
[device-scripts](https://github.com/AeroJudge/device-scripts). Its hardware prompts
and installation behavior are unchanged by the repository move.

1. Using the Raspberry Pi Imager available from the Raspberry site write the Raspberry Pi OS (32-bit) Desktop version to the SD card. Configure the relevant WiFi details, enable SSH and setup the user name judge (required) and password
	- username : judge
	- password : <*password*>
   <br>
2. Once complete insert the SD in to the rPI and boot. The initial boot will take some time as the system will expand the SD card's file system and configure the user and wifi details.
   <br>
3. Some screens require drivers to work, if your sreen needs this then install it now. Installing at the end will overwrite the gpio key bindings needed for the buttons to work, if you dont't require screen drivers skip to #5
<br>

4. These screen installation instructions are for WaveShare screens, the example below is for for the 3.5" IPS v2 screen. In the LCD-show folder once downlaoded you'll fine the relivant WaveShare SPI drivers for your screen
```
git clone https://github.com/waveshare/LCD-show.git
cd LCD-show/
chmod +x LCD35B-show-V2
./LCD35B-show-V2
```
<br>

5. Now run the following commands
```
cd /home/judge
wget -O judge_setup_legacy.sh https://raw.githubusercontent.com/AeroJudge/device-scripts/main/judge_setup_legacy.sh
chmod +x judge_setup_legacy.sh
./judge_setup_legacy.sh
```
<br>

6. Once the script is complete and the system is rebooted it will take about 2min for AeroJudge Device to start, then you should be able to browse to **http://rPI-IP:8080** from your PC or if your screen is connected, you should see AeroJudge Device loaded.
<br>
<br>

# AeroJudge Device App Setup From Pre Built SD

1. Using the Raspberry Pi Imager write the Raspberry Pi OS (32-bit) to the SD card.
   <br>
2. Once the image has complete, remove and re-insert the SD into your PC on the bootfs volume rename the file **wpa_supplicant.conf.bak** to  **wpa_supplicant.conf** and open the file for editing.
   <br>
3. Replace \<Country Code>, \<SSID>, and \<PASSWORD> with your own country code (US), WiFi SSID and password.
   <br>
4. On the bootfs volume edit the settings.json and update with the relevant details:
   - judge_id = (1-x) We'll use this id to post the score to Score as judge 1-x
   - score_host = This is the IP address that score will be running on, it's advisable to set a reservation on your AP for the Score Laptop so the IP never changes
   - score_http_port = The port you'll configure Score to listen on
   - line_number = This is the flight line if you are running multiple flight lines ( Leave it as 1 for now)
   - language = This will be used to determine which audio files to use. (Currently on being used)
   <br>
5. Once complete insert the SD in to the rPI and boot.
   <br>
6. At this point we might need to install drivers for the screen for WaveShare 3.5" Screens follow the commands below, please ensure at the LCD35B-show-V2 lines replace this with the relevant command based on your screen of choice. If your screen is already working correctly please skip this step
***Reference here :*** https://www.waveshare.com/wiki/Main_Page#Display-LCD-OLEDs
    ```
	git clone https://github.com/waveshare/LCD-show.git
	cd LCD-show/
	chmod +x LCD35B-show-V2
	./LCD35B-show-V2
	./LCD35B-show-V2 180
	```
	<br>


# AeroJudge Device App Setup From Scratch

The purpose of this document is to set out the process to the build a Raspberry PI judging unit from ground up. This document assumes that you are familiar with basic linux commands and SSH access into a linux terminal.

1. Using the Raspberry Pi Imager available from the Raspberry site write the Raspberry Pi OS (32-bit) to the SD card. Configure the relevant WiFi details, enable SSH and setup the user name judge (required) and password
	- username : judge
	- password : <*password*>
   <br>
2. Once the image has complete, remove and re-insert the SD into your PC, this should remount the SD card with an additional drive attached to your PC labled bootfs
   <br>
3. If you did not configure the WiFi in the previous step on the bootfs volume create a file called **wpa_supplicant.conf** with the following information replace **\<Country Code>**, **\<SSID>**, and **\<PASSWORD>** with your own country code **US**, WiFi SSID **ScoreBox**, and password.
_Note: The < > brackets are not part of the file - they only indicate these are placeholders._
	```
	ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
	update_config=1
	country=<Country Code>

	network={
		ssid="<SSID>"
		psk="<PASSWORD>"
		scan_ssid=1
	}
	```
	<br>
4. On the bootfs volume create a new file called settings.json and add the information below with the relevant details
	```
	{
		"judge_id":1,
		"line_number":1,
		"score_host":"192.168.1.4",
		"score_http_port":8181,
		"language":"en"
	}
	```

    - judge_id = (1-x) We'll use this ID to post the score to Score as judge 1-x
	- score_host = This is the IP address that score will be running on, it's advisable to set a reservation on your AP for the Score Laptop so the IP never changes
	- score_http_port = The port you'll configure Score to listen on
	- line_number = This is the flight line if you are running multiple flight lines (Leave it as 1 for now)
	- language = This will be used to determine which audio files to use. currently we are only supporting English so leave this unchanged
	<br>
5. Once complete insert the SD in to the rPI and boot. The inital boot will take some time as the system will expand the SD card's file system and configure the user and wifi details.
   <br>
6. Using a tool like Ping, or looking on your Router AP, determine the IP address of the PI and SSH into the rPI to configure the system swapfile for improved performance (if using an older Pi), We are going to update the swap to 512MB
    ```
	sudo dphys-swapfile swapoff
	sudo vi /etc/dphys-swapfile

	sudo dphys-swapfile setup
	sudo dphys-swapfile swapon
	```
	<br>
7. While still SSH'd to the rPI, run the the following to update the OS
	```
	echo "deb http://mirror.ox.ac.uk/sites/archive.raspbian.org/archive/raspbian bullseye main contrib non-free rpi" | sudo tee -a /etc/apt/sources.list
	sudo apt update
	sudo apt upgrade -y
	```
	<br>
8. Now we will remove any unused or unwanted  packages to improve performance
   ```
   sudo apt purge wolfram-engine scratch nuscratch sonic-pi idle3 -y
   sudo apt purge smartsim java-common libreoffice* lxplug-updater -y
   sudo apt clean
   sudo apt autoremove -y
   ```
   <br>
9. Here we are going to configure the boot options to auto login to the desktop so that the judge app will auto load
   ```
   sudo raspi-config
   # 1 System Options --> S5 Boot / Auto Login --> B4 Desktop Autologin — Desktop GUI --> automatically logged in as ‘judge’ user:
   ```
   <br>
10. We are going to install useful and needed packages
    ```
	sudo apt install vim openjdk-17-jre xdotool unclutter sed locate vim -y
	sudo apt clean
	sudo apt autoremove -y
	```
	```
	echo "set mouse-=a" | sudo tee -a /root/.vimrc
	echo "set mouse-=a" | sudo tee -a /home/judge/.vimrc
	```
	<br>
11. Disable IPV6 add ”ipv6.disable=1″ to the end of the line
    ```
	sudo vi /boot/cmdline.txt
	```
	<br>
12. At this point we might need to install drivers for the screen for WaveShare 3.5" Screens follow the commands below, please ensure at the LCD35B-show-V2 lines replace this with the relevant command based on your screen of choice. If your screen is already working correctly please skip this step
***Reference here :*** https://www.waveshare.com/wiki/Main_Page#Display-LCD-OLEDs
    ```
	git clone https://github.com/waveshare/LCD-show.git
	cd LCD-show/
	chmod +x LCD35B-show-V2
	./LCD35B-show-V2
	./LCD35B-show-V2 180
	```
	<br>
13. Configure and touch calibrations
    ```
	sudo apt install xinput-calibrator
	```
	<br>
14. Run the calibrations from the desktop and update the calibration.conf
    sudo vi /etc/X11/xorg.conf.d/99-calibration.conf
    ```
		Section "InputClass"
			Identifier		"calibration"
			MatchProduct	"ADS7846 Touchscreen"
			Option	"Calibration" "277 3995 3849 212"
		EndSection
	```
	<br>
15. Setup LCD FPS performance improvements edit the config.txt file on the bootfs partition and add to the bottom of the line
    sudo vi /boot/config.txt
    ```
	dtoverlay=disable-bt
	dtparam=speed=41000000
	dtparam=fps=30
	```
	<br>
16. Configure GPIO to Keyboard Mappings edit the config.txt file on the bootfs partition, You'll need to use the correct gpio as per your connection and button locations.
    sudo vi /boot/config.txt
    ```
	# gpio-key
	dtoverlay=gpio-key,gpio=26,active_low=1,gpio_pull=up,keycode=2  # Not Observer
	dtoverlay=gpio-key,gpio=27,active_low=1,gpio_pull=up,keycode=3  # -0.5
	dtoverlay=gpio-key,gpio=4,active_low=1,gpio_pull=up,keycode=4   # -1
	dtoverlay=gpio-key,gpio=5,active_low=1,gpio_pull=up,keycode=5  # encoder up/previous
	dtoverlay=gpio-key,gpio=3,active_low=1,gpio_pull=up,keycode=6   # zero
	dtoverlay=gpio-key,gpio=22,active_low=1,gpio_pull=up,keycode=7  # encoder down/next
	dtoverlay=gpio-key,gpio=2,active_low=1,gpio_pull=up,keycode=8  # break
	dtoverlay=gpio-key,gpio=6,active_low=1,gpio_pull=up,keycode=9   # +0.5
	dtoverlay=gpio-key,gpio=13,active_low=1,gpio_pull=up,keycode=10  # +1
	dtoverlay=gpio-key,gpio=19,active_low=1,gpio_pull=up,keycode=11  #speak
	```
	```
	These are the mappings NUM_KEY to keycode
	\#define KEY_1			2
	\#define KEY_2			3
	\#define KEY_3			4
	\#define KEY_4			5
	\#define KEY_5			6
	\#define KEY_6			7
	\#define KEY_7			8
	\#define KEY_8			9
	\#define KEY_9			10
	\#define KEY_0			11
	```
	<br>
17. Download the four app service/launcher files from `aerojudge-device-app`
    and the updater from `device-scripts` into `/home/judge`:

    ```sh
    cd /home/judge
    (
      set -e
      app_source=https://raw.githubusercontent.com/AeroJudge/aerojudge-device-app/main/scripts
      scripts_source=https://raw.githubusercontent.com/AeroJudge/device-scripts/main

      for file in judge.sh judge.service kiosk.sh kiosk.service; do
        curl -fsSL "$app_source/$file" -o "$file"
      done
      curl -fsSL "$scripts_source/judge_update.sh" -o judge_update.sh
    )
    ```

    Continue only if all five downloads succeed. Install the judging software:
    ```

	sudo mkdir /var/opt/judge
	sudo chown judge:judge /var/opt/judge
	mkdir /var/opt/judge/bin

	mv judge.sh /var/opt/judge/bin
	chmod +x /var/opt/judge/bin/judge.sh

	sudo mv judge.service /lib/systemd/system/
	sudo systemctl enable judge.service

	mv kiosk.sh /var/opt/judge/bin
	chmod +x /var/opt/judge/bin/kiosk.sh

	sudo mv kiosk.service /lib/systemd/system/
	sudo systemctl enable kiosk.service

	sudo ln -s /boot/settings.json /var/opt/judge/settings.json

	chmod +x judge_update.sh
	./judge_update.sh

	```

18. Reboot : On the first boot the Judge-App will attempt to connect to Score and retrieve the current Pilots and Sequences, you will need to run Score create a comp and enable the service in the services tab with the correct port. You can also from you PC once the PI has rebooted browse to http://PI-IP:8080/newcomp
    ```
	sudo reboot
	```
