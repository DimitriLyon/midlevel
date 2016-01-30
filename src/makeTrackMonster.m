function [firstCompleteFrame, monster] = makeTrackMonster(trackspec, featurelist)

% inputs:
%   trackspec: includes au pathname plus track (left or right)
%   fsspec: feature set specification
% output:
%   monster is a large 2-dimensional array, 
%     where every row is a timepoint, 20ms apart, starting at 20ms
%     and every column a feature
%   firstCompleteFrame, is the first frame for which all data tracks
%     are present.   This considers only the fact that the gaze
%     track may not have values up until frame x
%     It does not consider the fact that some of the wide past-value
%     features may not have meaningful values until some time into the data
%     The reason for this is that, in case the gaze data starts late,
%     we pad it with zeros, rather than truncating the audio.  This is because
%     we compute times using not timestamps, but implicitly, e.g. frame 0 
%     is anchored at time zero (in the audio track)
% efficiency issues: 
%   lots of redundant computation
%   compute everything every 10ms, then in the last step downsample to 20ms

% Nigel Ward, UTEP, 2014-2015

plotThings = false;

processGaze = false;
processKeystrokes = false;  
processAudio = false;
firstCompleteFrame = 1;
lastCompleteFrame = 9999999999999;

for featureNum = 1 : length(featurelist)
   thisfeature = featurelist(featureNum);
   %if ismember(thisfeature.featname, ['gf', 'gu', 'gd', 'gl', 'gr', 'go'])
   %previously the above commented line was used. it would evaluate rf is a member of the given set ['gf', 'gu', 'gd', 'gl', 'gr', 'go'], 
   %thus processGaze would be true
   %saif 
   if ismember(thisfeature.featname, {'ga'; 'gu'; 'gd'; 'gl'; 'gr'; 'go'})
       processGaze = true;
   end
   if  ismember(thisfeature.featname, ['rf', 'mi', 'ju'])
	processKeystrokes = true;
   end
   if  ismember(thisfeature.featname, ['vo', 'th', 'tl', 'lp', 'hp', 'fp', 'wp', 'np', 'sr', 'cr'])
	processAudio = true;
   end
end

if processGaze 
   [ssl, esl, gzl, gul, gdl, gll, grl, gfl] = ... 
       featurizeGaze(trackspec.path, 'l');
   [ssr, esr, gzr, gur, gdr, glr, grr, gfr] = ...
       featurizeGaze(trackspec.path, 'r');
   firstFullyValidTime = max(ssl, ssr);  % presumably always > 0
   firstCompleteFrame = ceil(firstFullyValidTime * 100);
   lastCompleteFrame = min(length(gzl), length(gzr));
end 

if processKeystrokes 
   [wrf wju wmi] = featurizeKeystrokes(trackspec.path, 'W', 100000);
   [frf fju fmi] = featurizeKeystrokes(trackspec.path, 'F', 100000);
end

  msPerFrame = 10; 

if processAudio 
  % ------ First, compute frame-level features: left track then right track ------
  [rate, signalPair] = readtracks(trackspec.path);

  samplesPerFrame = msPerFrame * (rate / 1000);
  plotEndSec = 8;  % plot the first few seconds of the signal and featueres

  [plraw, pCenters] = lookupOrComputePitch(...
        trackspec.directory, [trackspec.filename 'l'], signalPair(:,1), rate);
  [prraw, pCenters] = lookupOrComputePitch( ...
	trackspec.directory, [trackspec.filename 'r'], signalPair(:,2), rate);

  energyl = computeLogEnergy(signalPair(:,1)', samplesPerFrame);
  energyr = computeLogEnergy(signalPair(:,2)', samplesPerFrame);

 %pitchl = plraw; pitchr = prraw;  % old
 [pitchl, pitchr] = killBleeding(plraw, prraw, energyl, energyr); 

nframes = floor(length(signalPair(:,1)) / samplesPerFrame);
lastCompleteFrame = min(nframes, lastCompleteFrame);

% --- plot left-track signal, for visual inspection ---
if  plotThings
  hold on
  yScalingSignal = .005;
  yScalingEnergy = 6;
  plot(1/rate:1/rate:plotEndSec, signalPair(1:rate*plotEndSec,1)* yScalingSignal);
  % plot pitch, useful for checking for uncorrected bleeding
  pCentersSeconds = pCenters / 1000;
  pCentersToPlot = pCentersSeconds(pCentersSeconds<plotEndSec);
  scatter(pCentersToPlot, pitchl(1:length(pCentersToPlot)), 'g', '.');
  scatter(pCentersToPlot, 0.5 * pitchl(1:length(pCentersToPlot)), 'y', '.'); % halved
  scatter(pCentersToPlot, 2.0 * pitchl(1:length(pCentersToPlot)), 'y', '.'); % doubled
  offset = 0;  
  scatter(pCentersToPlot, pitchr(1:length(pCentersToPlot)) + offset, 'k.');   
  %plot((1:length(energyl)) * msPerFrame, energyl * yScalingEnergy,'g') 
  xlabel('seconds');
end

maxPitch = 500;
pitchLper = percentilizePitch(pitchl, maxPitch);
pitchRper = percentilizePitch(pitchr, maxPitch);

end 

% ------ Second, compute derived features, and add to monster ------


for featureNum = 1 : length(featurelist)
  thisfeature = featurelist(featureNum);
  duration = thisfeature.duration;
  startms = thisfeature.startms;
  endms = thisfeature.endms;
  feattype = thisfeature.featname;
  side = thisfeature.side;
  plotcolor = thisfeature.plotcolor;

  if processAudio
    if (strcmp(side,'self') && strcmp(trackspec.side,'l')) || ...
       (strcmp(side,'inte') && strcmp(trackspec.side,'r'))
      relevantPitch = pitchl;
      relevantPitchPer = pitchLper;
      relevantEnergy = energyl;
    else 
      relevantPitch = pitchr;
      relevantPitchPer = pitchRper;
      relevantEnergy = energyr;
    end
  end 

  if processGaze
    if (strcmp(side,'self') && strcmp(trackspec.side,'l')) || ...
	  (strcmp(side,'inte') && strcmp(trackspec.side,'r'))
      relGz = gzl; relGu = gul; relGd = gdl; relGl = gll; relGr = grl; relGa = gfl;
    else
      relGz = gzr; relGu = gur; relGd = gdr; relGl = glr; relGr = grr; relGa = gfr;
    end
  end

  if processKeystrokes
    if (strcmp(side,'self') && strcmp(trackspec.sprite,'W')) || ...
       (strcmp(side,'inte') && strcmp(trackspec.sprite,'F'))
       relevantJU = wju; relevantMI = wmi; relevantRF = wrf;
    else 
       relevantJU = fju; relevantMI = fmi; relevantRF = frf;
    end
  end

%  fprintf('processing feature %s %d %d %s \n', ...
%	  feattype, thisfeature.startms, thisfeature.endms, side); 
    
  switch feattype
    case 'vo'    % volume/energy/intensity/amplitude
      featurevec = windowEnergy(relevantEnergy, duration)';  % note, transpose
    case 'th'    % pitch truly high-ness
      featurevec = computePitchInBand(relevantPitchPer, 'th', duration);
    case 'tl'    % pitch truly low-ness
      featurevec = computePitchInBand(relevantPitchPer, 'tl', duration);
    case 'lp'    % pitch lowness 
      featurevec = computePitchInBand(relevantPitchPer, 'l', duration);
    case 'hp'    % pitch highness
      featurevec = computePitchInBand(relevantPitchPer, 'h', duration);
    case 'fp'    % flat pitch range 
      featurevec  = computePitchRange(relevantPitch, duration,'f')';
    case 'np'    % narrow pitch range 
      featurevec  = computePitchRange(relevantPitch, duration,'n')';
    case 'wp'    % wide pitch range 
      featurevec  = computePitchRange(relevantPitch, duration,'w')'; 
    case 'sr'    % speaking rate 
      featurevec = computeRate(relevantEnergy, duration)';
    case 'cr'    % creakiness
      featurevec = computeCreakiness(relevantPitch, duration); 

    case 'rf'    % running fraction
      featurevec = windowize(relevantRF, duration)';  % note, transpose
    case 'mi'    % motion initiation
      featurevec = windowize(relevantMI, duration)';  % note, transpose
    case 'ju'    % jumps
      featurevec = windowize(relevantJU, duration)';  % note, transpose

    case 'go'
      if duration == 0          % then we just want to predict it 
        featurevec = relGz(1:end-1)';
      else 
	featurevec = windowize(relGz, duration)'; 
      end 
    case 'gu'
      featurevec = windowize(relGu, duration)';
    case 'gd'
      featurevec = windowize(relGd, duration)';
    case 'gl'
      featurevec = windowize(relGl, duration)';
    case 'gr'
      featurevec = windowize(relGr, duration)';
    case 'ga'
      featurevec = windowize(relGa, duration)'; 

    otherwise
      warning([feattype ' :  unknown feature type']);
  end 
  
  [h, w] = size(featurevec);
  %fprintf('    size of featurevec is %d, %d\n', h, w);

  
% time-shift values as appropriate, either up or down (backward or forward in time)
% the first value of each featurevec represents the situation at 10ms or 15ms
  centerOffsetMs = (startms + endms) / 2;     % offset of the window center
  shift = round(centerOffsetMs / msPerFrame);
  if (shift == 0)
    shifted = featurevec;
  elseif (shift < 0)
    % then we want data from the past, so move it forward in time, 
    % by stuffing zeros in the front 
    shifted = [zeros(-shift,1); featurevec(1:end+shift)];  
  else 
    % shift > 0: want data from the future, so move it backward in time,
    % padding with zeros at the end
    shifted = [featurevec(shift+1:end); zeros(shift,1)];  
  end

  if plotThings && plotcolor ~= 0
     plot(pCentersToPlot, featurevec(1:length(pCentersToPlot)) * 100, plotcolor);
  end 
  % might convert from every 10ms to every 20ms to same time and space,
  % here, instead of doing it at the very end in writePcFilesBis
  %  downsampled = shifted(2:2:end);   
 
  shifted = shifted(1:lastCompleteFrame-1);

  features_array{featureNum} = shifted;  % append shifted values to monster
end   % loop back to do the next feature

monster = cell2mat(features_array);  % flatten it to be ready for princomp


% this is tested by calling findDimensions for a small audio file (e.g. short.au)
%  and a small set of features (e.g. minicrunch.fss)
% and then uncommenting various of the "scatter" commands above
%  and examining whether the feature values look appropriate for the audio input