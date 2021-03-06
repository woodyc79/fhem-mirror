    ##############################################
    ##############################################
    # $Id$
    # 
    # The purpose of this module is to support serval 
    # weather sensors like WS-0101  (Sender 868MHz ASK   Epmfänger RX868SH-DV elv)
    # Sidey79 & pejonp 2015  
    #
    package main;
    
    use strict;
    use warnings;
    use Digest::CRC qw(crc);
    
    #use Math::Round qw/nearest/;
    
    sub SD_WS09_Initialize($)
    {
      my ($hash) = @_;
    
      $hash->{Match}     = "^P9#[A-Fa-f0-9]+";    ## pos 7 ist aktuell immer 0xF
      $hash->{DefFn}     = "SD_WS09_Define";
      $hash->{UndefFn}   = "SD_WS09_Undef";
      $hash->{ParseFn}   = "SD_WS09_Parse";
      $hash->{AttrFn}	 = "SD_WS09_Attr";
      $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 "
                            ."windKorrektur:-3,-2,-1,0,1,2,3 "
                            ."$readingFnAttributes ";
      $hash->{AutoCreate} =
            { "SD_WS09.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.* windKorrektur:.*:0 " , FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"} };
    
    
    }
    
    #############################
    sub SD_WS09_Define($$)
    {
      my ($hash, $def) = @_;
      my @a = split("[ \t][ \t]*", $def);
    
      return "wrong syntax: define <name> SD_WS09 <code> ".int(@a)
            if(int(@a) < 3 );
    
      $hash->{CODE} = $a[2];
      $hash->{lastMSG} =  "";
      $hash->{bitMSG} =  "";
    
      $modules{SD_WS09}{defptr}{$a[2]} = $hash;
      $hash->{STATE} = "Defined";
      
      my $name= $hash->{NAME};
      return undef;
    }
    
    #####################################
    sub SD_WS09_Undef($$)
    {
      my ($hash, $name) = @_;
      delete($modules{SD_WS09}{defptr}{$hash->{CODE}})
         if(defined($hash->{CODE}) &&
            defined($modules{SD_WS09}{defptr}{$hash->{CODE}}));
      return undef;
    }
    
    
    ###################################
    sub SD_WS09_Parse($$)
    {
      my ($iohash, $msg) = @_;
      my $name = $iohash->{NAME};
      my (undef ,$rawData) = split("#",$msg);
      my @winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");
      my $hlen = length($rawData);
      my $blen = $hlen * 4;
      my $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 
      my $bitData2;
      my $bitData20;
      my $rain = 0;
      my $deviceCode = 0;
      my $model = "undef";  # 0xFFA -> WS0101/WH1080 alles andere -> CTW600 
      my $modelattr ;
      my $modelid;
      my $windSpeed = 0;
      my $windguest =0;
      my $sensdata;
      my $id;
      my $bat = 0;
      my $temp;
      my $hum;
      my $windDirection ;
      my $windDirectionText;
      
      
      $modelattr = AttrVal($iohash->{NAME},'WS09_WSModel',0);
      if ($modelattr eq '0'){
      $modelattr = "undef";
      }
      
      my $crcwh1080 = AttrVal($iohash->{NAME},'WS09_CRCAUS',0);
      Log3 $iohash, 3, "$name: SD_WS09_Parse CRC_AUS:$crcwh1080 Model=$modelattr" ;
    
      my $syncpos= index($bitData,"11111110");  #7x1 1x0 preamble
    	Log3 $iohash, 3, "$name: SD_WS09_Parse0 Bin=$bitData syncp=$syncpos length:".length($bitData) ;

    		if ($syncpos ==-1 || length($bitData)-$syncpos < 78) 
    		{
    			Log3 $iohash, 3, "$name: SD_WS09_Parse EXIT: msg=$rawData syncp=$syncpos length:".length($bitData) ;
    			return undef;
    		}

         my $wh = substr($bitData,0,8);
         #CRC-Check bei WH1080/WS0101 WS09_CRCAUS=0 und WS09_WSModel = undef oder Wh1080 
         if(($crcwh1080 == 0) &&  ($modelattr ne "CTW600")) {
             if($wh == "11111111") {
        	if ($syncpos == 0) 
    		{
          $hlen = length($rawData);
          $blen = $hlen * 4;
    	    $bitData2 = '11'.unpack("B$blen", pack("H$hlen", $rawData));
          $bitData20 = substr($bitData2,0,length($bitData2)-2);
          $blen = length($bitData20);
          $hlen = $blen / 4;
          $msg = 'P9#'.unpack("H$hlen", pack("B$blen", $bitData20));
          $bitData = $bitData20;
      	  Log3 $iohash, 3, "$name: SD_WS09_Parse sync1 msg=$msg syncp=$syncpos length:".length($bitData) ;
       		}
        
        	if ($syncpos == 1) 
    		{
          $hlen = length($rawData);
          $blen = $hlen * 4;
    	    $bitData2 = '1'.unpack("B$blen", pack("H$hlen", $rawData));
          $bitData20 = substr($bitData2,0,length($bitData2)-1);
          $blen = length($bitData20);
          $hlen = $blen / 4;
          $msg = 'P9#'.unpack("H$hlen", pack("B$blen", $bitData20));
          $bitData = $bitData20;           
      	  Log3 $iohash, 3, "$name: SD_WS09_Parse sync2 msg=$msg syncp=$syncpos length:".length($bitData) ;
       		}     
             
             
                my $datacheck = pack( 'H*', substr($msg,5,length($msg)-5) );
                my $crcmein = Digest::CRC->new(width => 8, poly => 0x31);
                my $rr2 = $crcmein->add($datacheck)->hexdigest;
                if ($rr2 eq "0"){
                    $model = "WH1080";
                    Log3 $iohash, 3, "$name: SD_WS09_Parse CRC_OK:  CRC=$rr2 Model=$model attr=$modelattr" ;
                }else{
                    Log3 $iohash, 3, "$name: SD_WS09_Parse CRC_Error:  msg=$msg CRC=$rr2 " ;
                    return undef;
                    }
            }else{
                $model = "CTW600";
                 Log3 $iohash, 3, "$name: SD_WS09_Parse CTW600:   Model=$model attr=$modelattr" ; 
                }
            };
                  
         if( ($wh == "11111111") || ($model eq "WH1080")) {
          if ($modelattr eq "CTW600"){
                    Log3 $iohash, 3, "$name: SD_WS09_WH1080 off=$modelattr Model=$model " ;
                    return undef;
              } 
            $sensdata = substr($bitData,8);
            my $whid = substr($sensdata,0,4);
            if(  $whid == "1010" ){ # A 
           	  Log3 $iohash, 3, "$name: SD_WS09_Parse WH=$wh msg=$sensdata syncp=$syncpos length:".length($sensdata) ;
              $model = "WH1080";
              $id = SD_WS09_bin2dec(substr($sensdata,4,8));
              $bat = (SD_WS09_bin2dec((substr($sensdata,64,4))) == 0) ? 'ok':'low' ; # decode battery = 0 --> ok
              $temp = (SD_WS09_bin2dec(substr($sensdata,12,12)) - 400)/10;
    		  $hum = SD_WS09_bin2dec(substr($sensdata,24,8));
              $windDirection = SD_WS09_bin2dec(substr($sensdata,68,4));  
              $windDirectionText = $winddir_name[$windDirection];
              $windSpeed =  round((SD_WS09_bin2dec(substr($sensdata,32,8))* 34)/100,01);
              Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." Windspeed bit: ".substr($sensdata,32,8)." Dec: " . $windSpeed ;
              $windguest = round((SD_WS09_bin2dec(substr($sensdata,40,8)) * 34)/100,01);
              Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." Windguest bit: ".substr($sensdata,40,8)." Dec: " . $windguest ;
              $rain =  SD_WS09_bin2dec(substr($sensdata,56,8)) * 0.3;
              Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." Rain bit: ".substr($sensdata,56,8)." Dec: " . $rain ;
            } else {
            if(  $whid == "1011" ){ # B  DCF-77 Zeitmeldungen vom Sensor
            my $hrs1 = substr($sensdata,16,8);
            my $hrs;
            my $mins; 
            my $sec; 
            my $mday;
            my $month;
            my $year;
            $id = SD_WS09_bin2dec(substr($sensdata,4,8));
            Log3 $iohash, 3, "$name: SD_WS09_Parse Zeitmeldung0: HRS1=$hrs1 id:$id" ;
            $hrs = SD_WS09_BCD2bin(substr($sensdata,18,6) ) ; # Stunde
            $mins = SD_WS09_BCD2bin(substr($sensdata,24,8)); # Minute 
            $sec = SD_WS09_BCD2bin(substr($sensdata,32,8)); # Sekunde 
            #day month year
            $year = SD_WS09_BCD2bin(substr($sensdata,40,8)); # Jahr
            $month = SD_WS09_BCD2bin(substr($sensdata,51,5)); # Monat
            $mday = SD_WS09_BCD2bin(substr($sensdata,56,8)); # Tag
            Log3 $iohash, 3, "$name: SD_WS09_Parse Zeitmeldung1:  msg=$rawData syncp=$syncpos length:".length($bitData) ;
            Log3 $iohash, 3, "$name: SD_WS09_Parse Zeitmeldung2: HH:mm:ss - ".$hrs.":".$mins.":".$sec ;
            Log3 $iohash, 3, "$name: SD_WS09_Parse Zeitmeldung3: dd.mm.yy - ".$mday.":".$month.":".$year ;
            return $name;
            }
                Log3 $iohash, 3, "$name: SD_WS09_Parse Zeitmeldung4: msg=$rawData syncp=$syncpos length:".length($sensdata) ;
    	          return undef;
            }
         }else{
              if ($modelattr eq "WH1080"){
                    Log3 $iohash, 3, "$name: SD_WS09_CTW600 off=$modelattr Model=$model " ;
                    return undef;
              } else {
            # eine CTW600 wurde erkannt 
            $sensdata = substr($bitData,$syncpos+8);
            Log3 $iohash, 3, "$name: SD_WS09_Parse CTW WH=$wh msg=$sensdata syncp=$syncpos length:".length($sensdata) ;
            $model = "CTW600";
            my $nn1 = substr($sensdata,10,2);  # Keine Bedeutung
            my $nn2 = substr($sensdata,62,4);  # Keine Bedeutung
            $modelid = substr($sensdata,0,4);
            Log3 $iohash, 3, "$name: SD_WS09_Parse Id: ".$modelid." NN1:$nn1 NN2:$nn2" ;
            Log3 $iohash, 3, "$name: SD_WS09_Parse Id: ".$modelid." Bin-Sync=$sensdata syncp=$syncpos length:".length($sensdata) ;
            $bat = SD_WS09_bin2dec((substr($sensdata,0,3))) ;
            $id = SD_WS09_bin2dec(substr($sensdata,4,6));
            $temp = (SD_WS09_bin2dec(substr($sensdata,12,10)) - 400)/10;
    	      $hum = SD_WS09_bin2dec(substr($sensdata,22,8));
            $windDirection = SD_WS09_bin2dec(substr($sensdata,66,4));  
            $windDirectionText = $winddir_name[$windDirection];
            $windSpeed =  round(SD_WS09_bin2dec(substr($sensdata,30,16))/240,01);
            Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." Windspeed bit: ".substr($sensdata,32,8)." Dec: " . $windSpeed ;
            $windguest = round((SD_WS09_bin2dec(substr($sensdata,40,8)) * 34)/100,01);
            Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." Windguest bit: ".substr($sensdata,40,8)." Dec: " . $windguest ;
            $rain =  round(SD_WS09_bin2dec(substr($sensdata,46,16)) * 0.3,01);
            Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." Rain bit: ".substr($sensdata,46,16)." Dec: " . $rain ;
            }
         }
        		
        Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." id:$id :$sensdata ";
        Log3 $iohash, 3, "$name: SD_WS09_Parse ".$model." id:$id, bat:$bat, temp=$temp, hum=$hum, winddir=$windDirection:$windDirectionText wS=$windSpeed, wG=$windguest, rain=$rain";
    
      if($hum > 100 || $hum < 0) {
            	Log3 $iohash, 3, "$name: SD_WS09_Parse HUM: hum=$hum msg=$rawData " ;
    			   return undef;
         } 
      if($temp > 60 || $temp < -40) {
            	Log3 $iohash, 3, "$name: SD_WS09_Parse TEMP: Temp=$temp msg=$rawData " ;
    			   return undef;
         } 
      
          
       my $longids = AttrVal($iohash->{NAME},'longids',0);
    	if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
    	{
    	 $deviceCode=$model."_".$id;
     		Log3 $iohash,4, "$name: SD_WS09_Parse using longid: $longids model: $model";
    	} else {
    		$deviceCode = $model;
    	}
       
        my $def = $modules{SD_WS09}{defptr}{$iohash->{NAME} . "." . $deviceCode};
        $def = $modules{SD_WS09}{defptr}{$deviceCode} if(!$def);
    
        if(!$def) {
    		Log3 $iohash, 1, 'SD_WS09_Parse UNDEFINED sensor ' . $model . ' detected, code ' . $deviceCode;
    		return "UNDEFINED $deviceCode SD_WS09 $deviceCode";
        }
    
      my $hash = $def;
    	$name = $hash->{NAME};	    	
    	Log3 $name, 4, "SD_WS09_Parse: $name ($rawData)";  
    
    
        my $windkorr = AttrVal($hash->{NAME},'windKorrektur',0);
        if ($windkorr != 0 )      
        {
        my $oldwinddir = $windDirection; 
        $windDirection = $windDirection + $windkorr; 
        $windDirectionText = $winddir_name[$windDirection];
        Log3 $iohash, 3, "SD_WS09_Parse ".$model." Faktor:$windkorr wD:$oldwinddir  Korrektur wD:$windDirection:$windDirectionText" ;
        }    
    
    	if (!defined(AttrVal($hash->{NAME},"event-min-interval",undef)))
    	{
    		my $minsecs = AttrVal($iohash->{NAME},'minsecs',0);
    		if($hash->{lastReceive} && (time() - $hash->{lastReceive} < $minsecs)) {
    			Log3 $hash, 4, "SD_WS09_Parse $deviceCode Dropped due to short time. minsecs=$minsecs";
    		  	return "";
    		}
    	}
    
    	$def->{lastMSG} = $rawData;
   
        my $state = "T: $temp ". ($hum>0 ? " H: $hum ":" ")." Ws: $windSpeed "." Wg: $windguest "." Wd: $windDirectionText "." R: $rain";
       
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "state", $state);
        readingsBulkUpdate($hash, "temperature", $temp)  if ($temp ne"");
        readingsBulkUpdate($hash, "humidity", $hum)  if ($hum ne "" && $hum != 0 );
        readingsBulkUpdate($hash, "battery", $bat)   if ($bat ne "");
        readingsBulkUpdate($hash, "id", $id) if ($id ne "");
        
        #zusätzlich Daten für Wetterstation
        readingsBulkUpdate($hash, "rain", $rain );
        readingsBulkUpdate($hash, "windGust", $windguest );
        readingsBulkUpdate($hash, "windSpeed", $windSpeed );
        readingsBulkUpdate($hash, "windDirection", $windDirection );
        readingsBulkUpdate($hash, "windDirectionDegree", $windDirection * 360 / 16);     
        readingsBulkUpdate($hash, "windDirectionText", $windDirectionText );
        readingsEndUpdate($hash, 1); # Notify is done by Dispatch
    
    	return $name;
    
    }
    
    sub SD_WS09_Attr(@)
    {
      my @a = @_;
    
      # Make possible to use the same code for different logical devices when they
      # are received through different physical devices.
      return  if($a[0] ne "set" || $a[2] ne "IODev");
      my $hash = $defs{$a[1]};
      my $iohash = $defs{$a[3]};
      my $cde = $hash->{CODE};
      delete($modules{SD_WS09}{defptr}{$cde});
      $modules{SD_WS09}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
      return undef;
    }
    
    
    sub SD_WS09_bin2dec($)
    {
      my $h = shift;
      my $int = unpack("N", pack("B32",substr("0" x 32 . $h, -32))); 
      return sprintf("%d", $int); 
    }
    sub SD_WS09_binflip($)
    {
      my $h = shift;
      my $hlen = length($h);
      my $i = 0;
      my $flip = "";
      
      for ($i=$hlen-1; $i >= 0; $i--) {
        $flip = $flip.substr($h,$i,1);
      }
    
      return $flip;
    }
    
    
    sub SD_WS09_BCD2bin($) {
      my $binary = shift;
      my $int = unpack("N", pack("B32", substr("0" x 32 . $binary, -32)));
      my $BCD = sprintf("%x", $int );
      return $BCD;
    }
    
    
    
    1;
    
    
=pod
=item summary    Supports weather sensors protocl 9 from SIGNALduino
=item summary_DE Unterst&uumltzt Wettersensoren mit Protokol 9 vom SIGNALduino
=begin html

<a name="SD_WS09"></a>
<h3>Wether Sensors protocol #9</h3>
<ul>
  The SD_WS09 module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  Requires Perl-Modul Digest::CRC. <br>
   <br> 
  cpan install Digest::CRC    or   sudo apt-get install libdigest-crc-perl <br>
   <br>
  <br>
  <b>Known models:</b>
  <ul>
    <li>WS-0101              --> Model: WH1080</li>
    <li>TFA 30.3189 / WH1080 --> Model: WH1080</li>
    <li>1073 (WS1080)        --> Model: WH1080</li>
    <li>CTW600               --> Model: CTW600 (??) </li> 
  </ul>
  <br>
  New received device are add in fhem with autocreate.
  <br><br>

  <a name="SD_WS09_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  The ID of the defice is the model or, if the longid attribute is specified, it is a combination of model and some random generated bits at powering the sensor.<br>
  If you want to use more sensors, you can use the longid option to differentiate them.
  </ul>
  <br>
  <a name="SD_WS09 Events"></a>
  <b>Generated readings:</b>
  <br>Some devices may not support all readings, so they will not be presented<br>
  <ul>
   <li>State (T: H: Ws: Wg: Wd: R: )  temperature, humidity, windSpeed, windGuest, windDirection, Rain</li>
     <li>Temperature (&deg;C)</li>
     <li>Humidity: (The humidity (1-100 if available)</li>
     <li>Battery: (low or ok)</li>
     <li>ID: (The ID-Number (number if)</li>
     <li>windSpeed (m/s) and windDirection (N-O-S-W)</li>
     <li>Rain (mm)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>Model<br>
        WH1080, CTW600
    </li><br>
    <li>windKorrektur<br>
      -3,-2,-1,0,1,2,3   
    </li><br>
   </ul>

  <a name="SD_WS09_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS09_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html
=begin html_DE

<a name="SD_WS09"></a>
<h3>SD_WS09</h3>
<ul>
  Das SD_WS09 Module verarbeitet von einem IO Gerät (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  Perl-Modul Digest::CRC erforderlich. <br>
   <br>
    cpan install Digest::CRC oder auch             <br>
    sudo apt-get install libdigest-crc-perl         <br>
   <br>
  <br>
  <b>Unterstütze Modelle:</b>
  <ul>
    <li>WS-0101              --> Model: WH1080</li>
    <li>TFA 30.3189 / WH1080 --> Model: WH1080</li>
    <li>1073 (WS1080)        --> Model: WH1080</li>
    <li>CTW600               --> Model: CTW600 (nicht getestet) </li>    
  </ul>
  <br>
  Neu empfangene Sensoren werden in FHEM per autocreate angelegt.
  <br><br>

  <a name="SD_WS09_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelegten Sensoren wird nach jedem Batteriewechsel ge&aumlndert, welche der Sensor beim Einschalten zuf&aumlllig vergibt.<br>
  CRC Checksumme wird zur Zeit noch nicht überpr&uumlft, deshalb werden Sensoren bei denen die Luftfeuchte < 0 oder > 100 ist, nicht angelegt.<br>
  </ul>
  <br>
  <a name="SD_WS09 Events"></a>
  <b>Generierte Readings:</b>
  <ul>
     <li>State (T: H: Ws: Wg: Wd: R: )  temperature, humidity, windSpeed, windGuest, windDirection, Rain</li>
     <li>Temperature (&deg;C)</li>
     <li>Humidity: (The humidity (1-100 if available)</li>
     <li>Battery: (low or ok)</li>
     <li>ID: (The ID-Number (number if)</li>
     <li>windSpeed (m/s) and windDirection (N-O-S-W)</li>
     <li>Rain (mm)</li>
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li>Model<br>
        WH1080, CTW600
    </li><br>
    <li>windKorrektur<br>
    Korrigiert die Nord-Ausrichtung des Windrichtungsmessers, wenn dieser nicht richtig nach Norden ausgerichtet ist. 
      -3,-2,-1,0,1,2,3    
    </li><br>
   </ul>

  <a name="SD_WS09_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="SD_WS09_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html_DE
=cut
