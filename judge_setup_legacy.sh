#!/bin/bash

SCRIPTS_RAW_BASE_URL="${AEROJUDGE_SCRIPTS_RAW_BASE_URL:-https://raw.githubusercontent.com/AeroJudge/device-scripts/main}"
RAW_BASE_URL="${AEROJUDGE_RAW_BASE_URL:-https://raw.githubusercontent.com/AeroJudge/aerojudge-device-app/main}"
RELEASE_API_URL="${AEROJUDGE_RELEASE_API_URL:-https://api.github.com/repos/AeroJudge/aerojudge-device-app/releases/latest}"

# Sources are independent: old base-image launchers export the app source.
while [ "${SCRIPTS_RAW_BASE_URL%/}" != "$SCRIPTS_RAW_BASE_URL" ]; do SCRIPTS_RAW_BASE_URL=${SCRIPTS_RAW_BASE_URL%/}; done
while [ "${RAW_BASE_URL%/}" != "$RAW_BASE_URL" ]; do RAW_BASE_URL=${RAW_BASE_URL%/}; done
export AEROJUDGE_SCRIPTS_RAW_BASE_URL="$SCRIPTS_RAW_BASE_URL"
export AEROJUDGE_RAW_BASE_URL="$RAW_BASE_URL"
export AEROJUDGE_RELEASE_API_URL="$RELEASE_API_URL"
clear
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Red='\033[0;31m'          # Red
NC="\033[0m" 			  # No Color

echo -e "${Green}Setting up your AeroJudge Scoring Device"
echo -e "${Red}Please note this script should only be run once !!!"

echo -e "${Yellow}Use swap file (older Pi) (y/n) ?"
read response

case $response in
	y|Y)
		# Setup Swap to 512MB
		echo -e "${Yellow}Setting swapfile to 512MB..."
		sudo dphys-swapfile swapoff 					> /dev/null 2>&1
		sudo sed -i 's/100/512/g' /etc/dphys-swapfile 	> /dev/null 2>&1
		sudo dphys-swapfile setup 						> /dev/null 2>&1
		sudo dphys-swapfile swapon 						> /dev/null 2>&1
		;;
esac

# Updating the OS
echo -e "${Yellow}Updating the OS..."
#echo "deb http://mirror.ox.ac.uk/sites/archive.raspbian.org/archive/raspbian bullseye main contrib non-free rpi" | sudo tee -a /etc/apt/sources.list > /dev/null 2>&1
sudo apt update 			> /dev/null 2>&1
sudo apt upgrade -y 		> /dev/null 2>&1


# Removing any unwanted packages
echo -e "${Yellow}Removing any unwanted packages..."
sudo apt purge wolfram-engine scratch nuscratch sonic-pi idle3 -y 	> /dev/null 2>&1
sudo apt purge smartsim java-common libreoffice* lxplug-updater -y 	> /dev/null 2>&1


# Install required packages
echo -e "${Yellow}Install required packages..."
sudo apt install vim openjdk-17-jre xdotool unclutter sed locate vim xinput-calibrator -y 	> /dev/null 2>&1
sudo apt clean 																				> /dev/null 2>&1
sudo apt autoremove -y 																		> /dev/null 2>&1

# Configure vim mouse preferances
echo -e "${Yellow}Configure vim..."
echo "set mouse-=a" | sudo tee -a /root/.vimrc 					> /dev/null 2>&1
echo "set mouse-=a" | tee -a /home/judge/.vimrc 			> /dev/null 2>&1

# Disable IPV6
echo -e "${Yellow}Disabling IPV6..."
echo "net.ipv6.conf.all.disable_ipv6 = 1" 		| sudo tee -a /etc/sysctl.conf 			> /dev/null 2>&1
echo "net.ipv6.conf.default.disable_ipv6 = 1" 		| sudo tee -a /etc/sysctl.conf 		> /dev/null 2>&1
echo "net.ipv6.conf.lo.disable_ipv6 = 1" 		| sudo tee -a /etc/sysctl.conf 			> /dev/null 2>&1
sudo sysctl -p > /dev/null 2>&1


# Disabling bluetooth
echo -e "${Yellow}Disabling bluetooth..."
echo "" 								| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
echo "#Disabling Bluetooth"				| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
echo "dtoverlay=disable-bt" 			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1


#Overclocking Pi to 800mhz
echo -e "${Yellow}Overclocking Pi to 800mhz..."						> /dev/null 2>&1
sudo sed -i 's/#arm_freq=800/arm_freq=800/g' /boot/config.txt 		> /dev/null 2>&1

#Setting Screen refresh Rate
echo -e "${Yellow}Setting Screen refresh Rate..."
echo "" 									| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
echo "#Setting Screen refresh Rate"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
echo "dtparam=speed=41000000" 				| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
echo "dtparam=fps=30" 						| sudo tee -a /boot/config.txt 		> /dev/null 2>&1


#Confgiuring gpio to key mappings
echo -e "${Yellow}Confgiuring gpio to key mappings..."
echo ""
echo -e "${Blue}Default gpio mapping:"
echo "Previous		= 5"
echo "+0.5 			= 6"
echo "+1.0 			= 13"
echo "Caller			= 19"
echo "Not Observed		= 26"
echo "Next 			= 22"
echo "-0.5 			= 27"
echo "-1.0 			= 4"
echo "Zero 			= 3"
echo "Break 			= 2"
echo ""

echo -e "${Yellow}GPIO Mappings"
echo -e "${Yellow}1 = Original Mappings"
echo -e "${Yellow}2 = AeroJudge Red board (No v#) Mappings"
echo -e "${Yellow}3 = AeroJudge Rev 2.5 (Blue board) Mappings"
echo -e "${Yellow}C = Custom Mappings (with custom keys)"

echo -e "${Yellow}Enter version of mappings to use (1,2,3, or C)"
read response

case $response in
	1)
		echo "Setting up default gpio to key mappings"
		echo ""																		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "#gpio key mappings" 													| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=22,active_low=1,gpio_pull=up,keycode=7"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # encoder down/next
		echo "dtoverlay=gpio-key,gpio=6,active_low=1,gpio_pull=up,keycode=9"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # +0.5
		echo "dtoverlay=gpio-key,gpio=13,active_low=1,gpio_pull=up,keycode=10"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # +1
		echo "dtoverlay=gpio-key,gpio=19,active_low=1,gpio_pull=up,keycode=11"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # caller
		echo "dtoverlay=gpio-key,gpio=26,active_low=1,gpio_pull=up,keycode=2"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # Not Observer
		echo "dtoverlay=gpio-key,gpio=5,active_low=1,gpio_pull=up,keycode=5"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # encoder up/previous
		echo "dtoverlay=gpio-key,gpio=27,active_low=1,gpio_pull=up,keycode=3"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # -0.5
		echo "dtoverlay=gpio-key,gpio=4,active_low=1,gpio_pull=up,keycode=4"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # -1
		echo "dtoverlay=gpio-key,gpio=3,active_low=1,gpio_pull=up,keycode=6"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # zero
		echo "dtoverlay=gpio-key,gpio=2,active_low=1,gpio_pull=up,keycode=8"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # break
		;;
	2)
		echo "Setting up AeroJudge red board (No v#) gpio to key mappings"
		echo ""																					| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "#gpio key mappings" 																| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=22,active_low=1,gpio_pull=up,keycode=2  # Not Observed"	| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=13,active_low=1,gpio_pull=up,keycode=3  # -0.5"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=6,active_low=1,gpio_pull=up,keycode=4   # -1"				| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=26,active_low=1,gpio_pull=up,keycode=5  # encoder up/previous"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=5,active_low=1,gpio_pull=up,keycode=6   # zero"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=19,active_low=1,gpio_pull=up,keycode=7  # encoder down/next"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=27,active_low=1,gpio_pull=up,keycode=8  # break"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=2,active_low=1,gpio_pull=up,keycode=9   # +0.5"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=3,active_low=1,gpio_pull=up,keycode=10  # +1"				| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=4,active_low=1,gpio_pull=up,keycode=11  #speak"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		;;
	3)
		echo "Setting up AeroJudge Rev 2.5 (Blue board) gpio to key mappings"
		echo ""																					| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "#gpio key mappings" 																| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=15,active_low=1,gpio_pull=up,keycode=5  # encoder up/previous"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=14,active_low=1,gpio_pull=up,keycode=10  # +1"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=22,active_low=1,gpio_pull=up,keycode=9   # +0.5"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=27,active_low=1,gpio_pull=up,keycode=11  # caller"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=4,active_low=1,gpio_pull=up,keycode=2  # Not Observed"	| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=20,active_low=1,gpio_pull=up,keycode=7  # encoder down/next"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=21,active_low=1,gpio_pull=up,keycode=4   # -1"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=5,active_low=1,gpio_pull=up,keycode=3   # -0.5"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=6,active_low=1,gpio_pull=up,keycode=6  # 0"				| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=13,active_low=1,gpio_pull=up,keycode=8  # break"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo ""																					| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "#Shutdown and Power Off button commands (SN DPG-061 and above)" 					| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-shutdown,gpio_pin=25,active_low=1,gpio_pull=up,debounce=3000"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-poweroff,gpiopin=24,active_delay_ms=5000,inactive_delay_ms=4000"	| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		;;
	c|C)
		echo "Enter the prefered gpio mappings"
		echo -e "${Blue}Previous :${NC}"
		read previous
		echo -e "${Blue}+0.5 :${NC}"
		read plus5
		echo -e "${Blue}+1.0 :${NC}"
		read plus1
		echo -e "${Blue}Caller :${NC}"
		read caller
		echo -e "${Blue}Not Observed :${NC}"
		read nob
		echo -e "${Blue}Next :${NC}"
		read next
		echo -e "${Blue}-0.5 :${NC}"
		read min5
		echo -e "${Blue}-1.0 :${NC}"
		read min1
		echo -e "${Blue}Zero :${NC}"
		read zero
		echo -e "${Blue}Break :${NC}"
		read break
		echo ""
		clear
		echo -e "${Yellow}Creating Mapping"
		echo "Previous 		:"$previous
		echo "+0.5 			:"$plus5
		echo "+1.0 			:"$plus1
		echo "Caller 			:"$caller
		echo "Not Observed 		:"$nob
		echo "Next 			:"$next
		echo "-0.5 			:"$min5
		echo "-1.0 			:"$min1
		echo "Zero 			:"$zero
		echo "Break 			:"$break
		echo ""
		echo ""																			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "#gpio key mappings" 														| sudo tee -a /boot/config.txt 		> /dev/null 2>&1
		echo "dtoverlay=gpio-key,gpio=$previous,active_low=1,gpio_pull=up,keycode=7"	| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # encoder down/next
		echo "dtoverlay=gpio-key,gpio=$plus5,active_low=1,gpio_pull=up,keycode=9"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # +0.5
		echo "dtoverlay=gpio-key,gpio=$plus1,active_low=1,gpio_pull=up,keycode=10"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # +1
		echo "dtoverlay=gpio-key,gpio=$caller,active_low=1,gpio_pull=up,keycode=11"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # caller
		echo "dtoverlay=gpio-key,gpio=$nob,active_low=1,gpio_pull=up,keycode=2"			| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # Not Observer
		echo "dtoverlay=gpio-key,gpio=$next,active_low=1,gpio_pull=up,keycode=5"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # encoder up/previous
		echo "dtoverlay=gpio-key,gpio=$min5,active_low=1,gpio_pull=up,keycode=3"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # -0.5
		echo "dtoverlay=gpio-key,gpio=$min1,active_low=1,gpio_pull=up,keycode=4"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # -1
		echo "dtoverlay=gpio-key,gpio=$zero,active_low=1,gpio_pull=up,keycode=6"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # zero
		echo "dtoverlay=gpio-key,gpio=$break,active_low=1,gpio_pull=up,keycode=8"		| sudo tee -a /boot/config.txt 		> /dev/null 2>&1  # break

		;;
esac

echo -e "${Yellow}Configure settings.json file..."

echo -e "${Blue}Judge_ID:${NC}"
read judgeid
echo -e "${Blue}Flight Line:${NC}"
read flightline
echo -e "${Blue}Score IP:${NC}"
read scoreip
echo -e "${Blue}Score Port${NC}"
read scoreport
echo -e "${Blue}Enter two digit year${NC}"
read seasonyear


echo -e "${Yellow}Creating settings.json file..."

echo '{'									| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"judge_id":'$judgeid','				| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"line_number":'$flightline','		| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"score_host":"'$scoreip'",'			| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"score_http_port":'$scoreport','	| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"language":"en",'					| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"score_poll_timeout":2,'			| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"score_timeout":10,'				| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '	"seasonYear":'$seasonyear''			| sudo tee -a /boot/settings.json	> /dev/null 2>&1
echo '}'									| sudo tee -a /boot/settings.json	> /dev/null 2>&1

echo -e "${Yellow}Configuring various settings..."
echo "export DISPLAY=:0" >> /home/judge/.bashrc
echo "xset r off # disable key repeat" >> /home/judge/.bashrc
echo "xset s off # disable screen saver " >> /home/judge/.bashrc
echo "xset -dpms # disable DPMS (Energy Star) features" >> /home/judge/.bashrc
echo "xset s noblank # disable screen blanking " >> /home/judge/.bashrc

echo -e "${Yellow}Setting up the AeroJudge Device App..."
sudo mkdir /var/opt/judge 																													> /dev/null 2>&1
sudo chown judge:judge /var/opt/judge 																										> /dev/null 2>&1
mkdir /var/opt/judge/bin 																													> /dev/null 2>&1

sudo wget -O /lib/systemd/system/judge.service "$RAW_BASE_URL/scripts/judge.service" 		> /dev/null 2>&1
wget -O /var/opt/judge/bin/judge.sh "$RAW_BASE_URL/scripts/judge.sh"							> /dev/null 2>&1
wget -O /home/judge/fetch_update.sh "$SCRIPTS_RAW_BASE_URL/fetch_update.sh"				> /dev/null 2>&1
chmod +x /home/judge/fetch_update.sh																									> /dev/null 2>&1
sudo wget -O /lib/systemd/system/kiosk.service "$RAW_BASE_URL/scripts/kiosk.service"			> /dev/null 2>&1
wget -O /var/opt/judge/bin/kiosk.sh "$RAW_BASE_URL/scripts/kiosk.sh"							> /dev/null 2>&1

wget -O /home/judge/ajdesktop.png "$SCRIPTS_RAW_BASE_URL/assets/ajdesktop.png"						> /dev/null 2>&1
pcmanfm --set-wallpaper /home/judge/ajdesktop.png --wallpaper-mode=stretch																	> /dev/null 2>&1

chmod +x /var/opt/judge/bin/judge.sh					> /dev/null 2>&1
sudo systemctl enable judge.service				    		> /dev/null 2>&1
sudo chmod +x /var/opt/judge/bin/kiosk.sh					> /dev/null 2>&1
sudo systemctl enable kiosk.service				    		> /dev/null 2>&1
sudo ln -s /boot/settings.json /var/opt/judge/settings.json	> /dev/null 2>&1

echo -e "${Yellow}Creating Default Pilots for Testing..."
wget -O /tmp/data.zip "$SCRIPTS_RAW_BASE_URL/assets/legacy/data.zip"						    > /dev/null 2>&1
unzip -o /tmp/data.zip -d /var/opt/judge/

/home/judge/fetch_update.sh

echo -e "${Yellow}AeroJudge Device App installation complete!"
