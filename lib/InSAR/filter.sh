#!/usr/bin/env bash

#################################################################
#
# Create interferometric datasets using filter routines
#
# Based on GMTSAR's filter.csh by Xiaopeng Tong and David Sandwell.
# Usage: prep.sh master_scene slave_scene GMTSAR_config_file OSARIS_PATH boundary_box.xyz
#
################################################################


gmt set IO_NC4_CHUNK_SIZE classic
gmt set COLOR_MODEL = hsv
gmt set PROJ_LENGTH_UNIT = inch


# Set grdimage options

scale="-JX6.5i"
thresh="5.e-21"

if [ ! $# -eq 4 ] && [ ! $# -eq 6 ]; then
    echo ""
    echo "Usage: filter.sh master.PRM slave.PRM filter decimation [rng_dec azi_dec]"
    echo ""
    echo " Apply gaussian filter to amplitude and phase images."
    echo " "
    echo " filter -  wavelength of the filter in meters (0.5 gain)"
    echo " decimation - (1) better resolution, (2) smaller files"
    echo " "
    echo "Example: filter.sh IMG-HH-ALPSRP055750660-H1.0__A.PRM IMG-HH-ALPSRP049040660-H1.0__A.PRM 300  2"
    echo ""
    exit 1
fi


echo; echo "Creating interferometric datasets"; echo


# Filter and decimation variable setup

sharedir=$( gmtsar_sharedir.csh )
filter3=${sharedir}/filters/fill.3x3
filter4=${sharedir}/filters/xdir
filter5=${sharedir}/filters/ydir

dec=$4
az_lks=4 

PRF=$( grep PRF *.PRM | awk 'NR == 1 {printf("%d", $3)}' )

if [ $PRF -lt 1000 ]; then
    az_lks=1
fi


# Look for range sampling rate
rng_samp_rate=$( grep rng_samp_rate $1 | awk 'NR == 1 {printf("%d", $3)}' )

echo "rng_samp_rate: $rng_samp_rate"

# Set the range spacing in units of image range pixel size

if [ ! -z $rng_samp_rate ]; then
    echo; echo "Determining range spacing ..."; echo
    if [ $rng_samp_rate > 110000000 ]; then 
	dec_rng=4
	filter1=$sharedir/filters/gauss15x5
    elif [ $rng_samp_rate < 110000000 ] && [ $rng_samp_rate > 20000000 ]; then
	dec_rng=2
	filter1=$sharedir/filters/gauss15x5
	#
	# special for TOPS mode
	#
	if [ $az_lks == 1 ]; then
            filter1=$sharedir/filters/gauss5x5
	fi
    else  
	dec_rng=1
	filter1=$sharedir/filters/gauss15x3
    fi
else
    echo "Undefined rng_samp_rate in the master PRM file"
    exit 1
fi


#  Make the custom filter2 and set the decimation

make_gaussian_filter $1 $dec_rng $az_lks $3 > ijdec
filter2=gauss_$3
idec=`cat ijdec | awk -v dc="$dec" '{ print dc*$1 }'`
jdec=`cat ijdec | awk -v dc="$dec" '{ print dc*$2 }'`
if [ $#argv == 6 ]; then
    idec=`echo $6 $az_lks | awk '{printf("%d",$1/$2)}'`
    jdec=`echo $5 $dec_rng | awk '{printf("%d",$1/$2)}'`
    echo "Setting range_dec=$5, azimuth_dec=$6"
fi
echo "$filter2 $idec $jdec ($az_lks $dec_rng)" 


# Filter the two amplitude images

echo "Making amplitudes..."
conv $az_lks $dec_rng $filter1 $1 amp1_tmp.grd=bf
conv $idec $jdec $filter2 amp1_tmp.grd=bf amp1.grd
rm amp1_tmp.grd
conv $az_lks $dec_rng $filter1 $2 amp2_tmp.grd=bf
conv $idec $jdec $filter2 amp2_tmp.grd=bf amp2.grd
rm amp2_tmp.grd


# Filter the real and imaginary parts of the interferogram
# and compute gradients

echo; echo "Filtering interferogram..."
conv $az_lks $dec_rng $filter1 real.grd=bf real_tmp.grd=bf
conv $idec $jdec $filter2 real_tmp.grd=bf realfilt.grd
conv $dec $dec $filter4 real_tmp.grd xreal.grd
conv $dec $dec $filter5 real_tmp.grd yreal.grd
rm real_tmp.grd 
rm real.grd
conv $az_lks $dec_rng $filter1 imag.grd=bf imag_tmp.grd=bf
conv $idec $jdec $filter2 imag_tmp.grd=bf imagfilt.grd
conv $dec $dec $filter4 imag_tmp.grd ximag.grd
conv $dec $dec $filter5 imag_tmp.grd yimag.grd
rm imag_tmp.grd 
rm imag.grd


# Form amplitude image

echo; echo "Making amplitude..."
gmt grdmath realfilt.grd imagfilt.grd HYPOT  = amp.grd 
gmt grdmath amp.grd 0.5 POW FLIPUD = display_amp.grd 
# AMAX=`gmt grdinfo -L2 display_amp.grd | grep stdev | awk '{ print 3*$5 }'`
# gmt grd2cpt display_amp.grd -Z -D -L0/$AMAX -Cgray > display_amp.cpt
# echo "N  255   255   254" >> display_amp.cpt
# gmt grdimage display_amp.grd -Cdisplay_amp.cpt $scale -Bxaf+lRange -Byaf+lAzimuth -BWSen -X1.3i -Y3i -P -K > display_amp.ps
# gmt psscale -Rdisplay_amp.grd -J -DJTC+w5i/0.2i+h+ef -Cdisplay_amp.cpt -Bx0+l"Amplitude (histogram equalized)" -O >> display_amp.ps
# gmt psconvert -Tf -P -Z display_amp.ps
# echo "Amplitude map: display_amp.pdf"


# Form the correlation

echo; echo "Making coherence..."
gmt grdmath amp1.grd amp2.grd MUL = tmp.grd
gmt grdmath tmp.grd $thresh GE 0 NAN = mask.grd
gmt grdmath amp.grd tmp.grd SQRT DIV mask.grd MUL FLIPUD = tmp2.grd=bf
conv 1 1 $filter3 tmp2.grd=bf corr.grd
# gmt makecpt -T0./.8/0.1 -Cgray -Z -N > corr.cpt
# echo "N  255   255   254" >> corr.cpt
# gmt grdimage corr.grd $scale -Ccorr.cpt -Bxaf+lRange -Byaf+lAzimuth -BWSen -X1.3i -Y3i -P -K > corr.ps
# gmt psscale -Rcorr.grd -J -DJTC+w5i/0.2i+h+ef -Ccorr.cpt -Baf+lCorrelation -O >> corr.ps
# gmt psconvert -Tf -P -Z corr.ps
# echo "Correlation map: corr.pdf"


# Form the phase 

echo; echo "Making phase..."
gmt grdmath imagfilt.grd realfilt.grd ATAN2 mask.grd MUL FLIPUD = phase.grd
# gmt makecpt -Crainbow -T-3.15/3.15/0.1 -Z -N > phase.cpt
# gmt grdimage phase.grd $scale -Bxaf+lRange -Byaf+lAzimuth -BWSen -Cphase.cpt -X1.3i -Y3i -P -K > phase.ps
# gmt psscale -Rphase.grd -J -DJTC+w5i/0.2i+h -Cphase.cpt -B1.57+l"Phase" -By+lrad -O >> phase.ps
# gmt psconvert -Tf -P -Z phase.ps
# echo "Phase map: phase.pdf"

# compute the solid earth tide
# uncomment lines with ##
#
##ln -s ../../topo/dem.grd .
##tide_correction.csh $1 $2 dem.grd
##mv tide.grd tmp.grd
##gmt grdsample tmp.grd -Rimagfilt.grd -Gtide.grd


# Make the Werner/Goldstein filtered phase

echo; echo "Applying Werner/Goldstein filter to phase..."
phasefilt -imag imagfilt.grd -real realfilt.grd -amp1 amp1.grd -amp2 amp2.grd -psize 32 
gmt grdedit filtphase.grd `gmt grdinfo mask.grd -I- --FORMAT_FLOAT_OUT=%.12lg` 
gmt grdmath filtphase.grd mask.grd MUL FLIPUD = phasefilt.grd
##cp phasefilt.grd phasefilt_old.grd
##gmt grdmath phasefilt.grd tide.grd SUB PI ADD 2 PI MUL MOD PI SUB = phasefilt.grd
rm filtphase.grd
# gmt grdimage phasefilt.grd $scale -Bxaf+lRange -Byaf+lAzimuth -BWSen -Cphase.cpt -X1.3i -Y3i -P -K > phasefilt.ps
# gmt psscale -Rphasefilt.grd -J -DJTC+w5i/0.2i+h -Cphase.cpt -Bxa1.57+l"Phase" -By+lrad -O >> phasefilt.ps
# gmt psconvert -Tf -P -Z phasefilt.ps
# echo "Filtered phase map: phasefilt.pdf"


# Form the phase gradients

echo; echo "Making phase gradients ..."
gmt grdmath amp.grd 2. POW = amp_pow.grd
gmt grdmath realfilt.grd ximag.grd MUL imagfilt.grd xreal.grd MUL SUB amp_pow.grd DIV mask.grd MUL FLIPUD = xphase.grd
gmt grdmath realfilt.grd yimag.grd MUL imagfilt.grd yreal.grd MUL SUB amp_pow.grd DIV mask.grd MUL FLIPUD = yphase.grd 
#  gmt makecpt -Cgray -T-0.7/0.7/0.1 -Z -N > phase_grad.cpt
#  echo "N  255   255   254" >> phase_grad.cpt
#  gmt grdimage xphase.grd $scale -Cphase_grad.cpt -X.2i -Y.5i -P > xphase.ps
#  gmt grdimage yphase.grd $scale -Cphase_grad.cpt -X.2i -Y.5i -P > yphase.ps
#
mv mask.grd tmp.grd 
gmt grdmath tmp.grd FLIPUD = mask.grd
#
# delete files
rm tmp.grd tmp2.grd ximag.grd yimag.grd xreal.grd yreal.grd 
