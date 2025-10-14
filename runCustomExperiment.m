    %% runCustomExperiment.m
    % This function runs a custom experiment using vrControl. It is similar to runExperiment.m
    % but allows for more flexibility in setting up the experiment parameters and
    % trial structure.

function runCustomExperiment(expInfo, animal, session, trainingMode, wheelGain)

    %% 1. Set up some defaults for expSettings and trialStructure
    % TODO these should be loaded by the GUI
    expSettings.maxTrialNumber = 500;
    expSettings.maxTrialDuration = 60; % seconds

    expSettings.vrDirectory = '\\znas.cortexlab.net\Code\Rigging\ExpDefinitions\Jacob\vr_envs\'; % directory where VR environments are stored
    expSettings.vrOptions = {'VR_000_deg_poort_corridor_stack_000', 'VR_000_deg_poort_corridor_stack_001', 'VR_090_deg_poort_corridor_stack_000', 'VR_090_deg_poort_corridor_stack_001'}; % cell array of strings with names of VR environments (must match files in vrDirectory)
    expSettings.vrFrames = [200; 200; 200; 200]; % vector with number of frames in each VR environment
    expSettings.vrDSFactor = [1; 1; 1; 1]; % vector with downsampling factor for each VR environment
    expSettings.vrFramesDS = [200; 200; 200; 200]; % vector with number of frames after downsampling for each VR environment

    % Set up trialStructure (not needed?)
    % trialStructure.envIndex = []; % vector with indices of VR environments to use for each trial
    % trialStructure.envLength = []; % vector with lengths of each VR environment (in cm)
    trialStructure.getEnvPath = @(idx) fullfile(expSettings.vrDirectory, [expSettings.vrOptions{idx} '.tif']); % function handle to get full path of VR environment file based on index

    %% 2. Prepare expInfo and rigInfo structures

    % Load rig parameters
    rigInfo = rigParameters(); 
    rigInfo.wheelCircumference = 2*pi*rigInfo.wheelRadius; % ATTENTION TO MINUTE DETAIL

    % define the UDP port
    rigInfo = rigInfo.initialiseUDPports(rigInfo);

    % Modify loaded expInfo structure based on user input
    expInfo.trainingMode = trainingMode;
    expInfo.animalName = animal;
    expInfo.sessionName = session + 1; 
    expInfo.dateStr = datestr(now, 'yyyymmdd');
    while true
        % While loop ensures that the sessionName is novel
        expInfo.expRef = dat.constructExpRef(expInfo.animalName,now,expInfo.sessionName);
        expInfo.LocalDir = dat.expPath(expInfo.expRef, 'local', 'master');
        if exist(expInfo.LocalDir,'dir')
            expInfo.sessionName = expInfo.sessionName + 1; % try again
        else
            fprintf('Animal: %s --- Session Number: %d\n',expInfo.animalName, expInfo.sessionName);
            expInfo.sessionName = num2str(expInfo.sessionName);
            break
        end
    end

    % Create Directories (ATL: a lot of these are unnecessary...)
    expInfo.ServerDir = dat.expPath(expInfo.expRef, 'main', 'master');
    expInfo.AnimalDir = fullfile(expInfo.ServerDir, expInfo.animalName);
    if ~isfolder(expInfo.AnimalDir), mkdir(expInfo.AnimalDir); end
    if ~isfolder(expInfo.LocalDir), mkdir(expInfo.LocalDir); end
    expInfo.SESSION_NAME = fullfile(expInfo.LocalDir, [expInfo.expRef, '_VRBehavior']);
    expInfo.centralLogName = fullfile(rigInfo.dirSave, 'centralLog');
    expInfo.animalLogName  = [expInfo.AnimalDir filesep expInfo.animalName '_log'];

    %% From here on the code is the same as in runExperiment.m

    %% 3. Prepare hwInfo structure

    intializePsychToolboxString = 'Screen(''Preference'',''VisualDebugLevel'', 0)';
    evalc(intializePsychToolboxString);
    Screen('Preference', 'SkipSyncTests', 1);

    % Prepare Screen
    thisScreen = rigInfo.screenNumber;
    hwInfo.screenInfo = prepareScreenVR(thisScreen,rigInfo);

    % define synchronization square read by photodiode
    if strcmp(rigInfo.photodiodePos,'right')
        hwInfo.photodiodeRect = struct('rect',[(hwInfo.screenInfo.Xmax - rigInfo.photodiodeSize(1)) 0 ...
            hwInfo.screenInfo.Xmax      rigInfo.photodiodeSize(2) - 1], ...
            'colorOn', [1 1 1], 'colorOff', [0 0 0]);
    elseif strcmp(rigInfo.photodiodePos,'left')
        hwInfo.photodiodeRect = struct('rect',[0 0 rigInfo.photodiodeSize(1)-1  ...
            rigInfo.photodiodeSize(2)-1], ...
            'colorOn', [1 1 1], 'colorOff', [0 0 0]);
    end

    if ~rigInfo.useKeyboard
        hwInfo.BALLPort = 9999;
        % Setup wheel hardware info
        hwInfo.session = daq.createSession('ni');
        hwInfo.session.Rate = rigInfo.NIsessRate;
        hwInfo.rotEnc = hw.DaqRotaryEncoder;
        hwInfo.rotEnc.DaqSession = hwInfo.session;
        hwInfo.rotEnc.DaqId = rigInfo.NIdevID;
        hwInfo.rotEnc.DaqChannelId = rigInfo.NIRotEnc;
        hwInfo.rotEnc.createDaqChannel;
        hwInfo.rotEnc.zero();
        
        if expInfo.lickEncoder && ~isempty(rigInfo.NILicEnc)
            % Then we need to add a lick encoder
            hwInfo.likEnc = hw.DaqLickEncoder;
            hwInfo.likEnc.DaqSession = hwInfo.session;
            hwInfo.likEnc.DaqId = rigInfo.NIdevID;
            hwInfo.likEnc.DaqChannelId = rigInfo.NILicEnc;
            hwInfo.likEnc = hwInfo.likEnc.createDaqChannel;
        end
        
        hwInfo.sessionVal = daq.createSession('ni');
        hwInfo.sessionVal.Rate = rigInfo.NIsessRate;
        
        if rigInfo.useAnalogRewardValve
            hwInfo.rewVal = hw.DaqRewardValve_Analog;
        else
            hwInfo.rewVal = hw.DaqRewardValve;
        end
        load(rigInfo.WaterCalibrationFile);
        hwInfo.rewVal.DaqSession = hwInfo.sessionVal;
        hwInfo.rewVal.DaqId = rigInfo.NIdevID;
        hwInfo.rewVal.DaqChannelId = rigInfo.NIRewVal;
        hwInfo.rewVal.createDaqChannel;
        hwInfo.rewVal.MeasuredDeliveries = Water_calibs(end).measuredDeliveries;
        hwInfo.rewVal.OpenValue = 10;
        hwInfo.rewVal.ClosedValue = 0;
        
        if rigInfo.useAnalogRewardValve
            hwInfo.rewVal.close;
        else
            if rigInfo.rewardSizeByVolume
                hwInfo.rewVal.prepareRewardDelivery(rigInfo.waterVolumePASS, 'ul');
            else
                hwInfo.rewVal.prepareRewardDelivery(rigInfo.PASSvalveTime, 's');
            end
            hwInfo.rewVal.prepareDigitalTrigger()
        end

    else
        % setup keyboard situation
        KbName('UnifyKeyNames');
        hwInfo.moveForward = KbName('UpArrow');
        hwInfo.moveBackward = KbName('DownArrow');
        hwInfo.increaseSpeed = KbName('RightArrow');
        hwInfo.decreaseSpeed = KbName('LeftArrow');
        hwInfo.minKeyboardSpeed = 1; % cm
        hwInfo.maxKeyboardSpeed = 9; % cm
        hwInfo.stepKeyboardSpeed = 1; % cm
        hwInfo.keyboardSpeed = 3; % cm
    end


    %% 4. Prepare runInfo structure

    runInfo = [];
    runInfo.rewardStartT = timer('TimerFcn', 'reward(0.0)');
    runInfo.STOPrewardStopT= timer('TimerFcn', 'reward(1.0)','StartDelay', rigInfo.STOPvalveTime );
    runInfo.BASErewardStopT= timer('TimerFcn', 'reward(1.0)','StartDelay', rigInfo.BASEvalveTime );
    runInfo.currTrial = 0;
    runInfo.flipIdx = 0; % Counts flips throughout trial to store data in trialInfo
    runInfo.roomPosition = rigInfo.minimumPosition; % current position
    runInfo.move2NextTrial = 0;
    runInfo.rewardAvailable = 1; % FLAG to determine if reward has been delivered on current trial (set to 0 if delivered)
    runInfo.abort = 0; % turns to 1 if user aborts using the escape key
    runInfo.inRewardZone = false;
    runInfo.rewZoneTimerActive = false;
    runInfo.timeInRewardZone = [];
    runInfo.vrEnvIdx = [];
    runInfo.pdLevel = 0; % always start at 0 because we have a ramp up from 0 indicating the ITI!
    runInfo.totalValveOpenTime = 0; % for tracking duration of reward delivery
    runInfo.trialStartTime = []; % timer for tracking duration of trial
    runInfo.trainingTimer = tic;

    % Load VR Environment File(s)
    numOptions = length(expSettings.vrOptions);
    idxInUse = unique(expInfo.envIndex);
    runInfo.vrEnvs = cell(1,numOptions);
    fprintf(1, '#ATL: Loading environments from: %s\n', expSettings.vrDirectory);
    for vrOpt = 1:numOptions
        if ~ismember(vrOpt, idxInUse), continue, end % only load environments that are in use
        cpath = trialStructure.getEnvPath(vrOpt);
        vrTifInfo = imfinfo(cpath);
        height = vrTifInfo(1).Height;
        width = vrTifInfo(1).Width;
        if length(vrTifInfo) ~= expSettings.vrFrames(vrOpt)
            error('Handshake between expSettings and trialStructure did not work out (or some earlier issue with the GUI occurred).');
        end
        numVrFrames = expSettings.vrFramesDS(vrOpt);
        fprintf(1, '#ATL: Loading %s, downsampling from %i frames to %i frames (dsratio:%i)...\n',...
            trialStructure.getEnvName(vrOpt), expSettings.vrFrames(vrOpt), expSettings.vrFramesDS(vrOpt), expSettings.vrDSFactor(vrOpt));
        runInfo.vrEnvs{vrOpt} = zeros(height,width,3,numVrFrames,'uint8');
        for f = 1:numVrFrames
            runInfo.vrEnvs{vrOpt}(:,:,:,f) = uint8(imread(cpath,(f-1)*expSettings.vrDSFactor(vrOpt)+1));
        end
    end


    %% 5. Prepare trialInfo structure

    % We need to preallocate arrays for storing trial info from each vr frame
    % There's an estimated maximum number of frames per trial based on the
    % preferred refresh rate and the maximum trial duration
    % This overAllocate factor overestimates that to make sure no failure
    % occurs during the experiment
    overAllocate = 1.1 * (2*rigInfo.PrefRefreshRate) * expSettings.maxTrialDuration; 

    % Preallocate arrays for tracking data related to each trial
    trialInfo.trialIdx = sparse(zeros(expSettings.maxTrialNumber,1)); % trial idx (should count up)
    trialInfo.startTime = sparse(zeros(expSettings.maxTrialNumber,1)); % timestamp of trial start
    trialInfo.startPosition = sparse(zeros(expSettings.maxTrialNumber,1)); % initial position within virtual environment
    trialInfo.activeLicking = sparse(zeros(expSettings.maxTrialNumber,1)); % copy here for easy saving
    trialInfo.activeStopping = sparse(zeros(expSettings.maxTrialNumber,1)); % copy here for easy saving
    trialInfo.rewardPosition = sparse(zeros(expSettings.maxTrialNumber,1)); % copy here for easy saving
    trialInfo.rewardTolerance = sparse(zeros(expSettings.maxTrialNumber,1)); % copy here for easy saving
    trialInfo.vrEnvIdx = sparse(zeros(expSettings.maxTrialNumber,1)); % copy here for easy saving
    trialInfo.iti = sparse(zeros(expSettings.maxTrialNumber,1)); % duration of true ITI (always greater than minimum requested)
    trialInfo.outcome = sparse(zeros(expSettings.maxTrialNumber,1)); % was a reward delivered
    trialInfo.rewardDeliveryFrame = sparse(zeros(expSettings.maxTrialNumber,1)); % the "count"(flip idx) in which reward delivered
    trialInfo.rewardAvailable = sparse(zeros(expSettings.maxTrialNumber,1)); % boolean if reward was available on trial 
    trialInfo.userRewardNumber = sparse(zeros(expSettings.maxTrialNumber,1)); % the number of user rewards given (using spacebar)
    trialInfo.userRewardFrames = cell(expSettings.maxTrialNumber,1); % the frame idx during user reward delivery

    % Preallocate arrays for tracking data related to each frame
    trialInfo.time = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double'));
    trialInfo.lick = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double'));
    trialInfo.stop = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double')); 
    trialInfo.inRewardZone = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double')); 
    trialInfo.roomPosition = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double')); % position in corridor
    trialInfo.frameIdx = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double')); % which frame is on
    trialInfo.pdLevel = sparse(zeros(expSettings.maxTrialNumber, overAllocate,'double')); % whether the photodiode is up or down


    %% 6. Open vrUpdateWindow

    if expInfo.trainingMode
        expInfo.useUpdateWindow = true;
        updateWindow = vrControlTrainingWindow();
        updateWindow.setAvailableEnvironments(unique(expInfo.envIndex), expInfo.getEnvName);
        updateWindow.setCurrentTrial(1);
        updateWindow.envIdx.Value = expInfo.envIndex(1);
        updateWindow.minimumITI.Value = expInfo.intertrialInterval(1);
        updateWindow.envLength.Value = expInfo.roomLength(1);
        updateWindow.mvmtGain.Value = expInfo.mvmtGain(1);
        updateWindow.rewardPosition.Value = expInfo.rewardPosition(1);
        updateWindow.rewardTolerance.Value = expInfo.rewardTolerance(1);
        updateWindow.probReward.Value = expInfo.probReward(1);
        updateWindow.lickRequired.Value = expInfo.activeLick(1);
        updateWindow.stopRequired.Value = logical(expInfo.activeStop(1));
        updateWindow.stopDuration.Value = expInfo.activeStop(1);
    else
        if expInfo.useUpdateWindow
            updateWindow = vrControlUpdateWindow(); 
        end
    end


    %% -- now, prepare vrcontrol loop --

    fprintf('\nStarting MouseBall session %s\n', datestr(now, 'mm-dd'));
    GetSecs; %To get it started once

    VRLogMessage(expInfo);
    VRmessage = ['Starting new experiment with animal ' expInfo.animalName ':'];
    VRLogMessage(expInfo, VRmessage);
    VRLogMessage(expInfo);
    try
        VRmessage = ['ExpStart ' expInfo.animalName ' ' expInfo.dateStr ' ' expInfo.sessionName];
        rigInfo = rigInfo.sendUDPmessage(rigInfo, VRmessage);
        VRLogMessage(expInfo, VRmessage);
        if expInfo.useUpdateWindow
            disp('Press yellow start button to continue after confirming Timeline has started...')
            updateWindow.enableStart();
            waitfor(updateWindow, 'timelineActive', true);
        else
            disp('Press key to continue after confirming Timeline has started...')
            pause()
        end
    catch
        keyboard
    end

    runInfo.ititimer = tic; % Initialize this here (usually reset in operateTrial)
    fhandle = @prepareTrial;
    while ~isempty(fhandle) 
        % main loop, active during experiment
        [fhandle, runInfo, trialInfo, expInfo] = feval(fhandle, rigInfo, hwInfo, expInfo, runInfo, trialInfo, updateWindow);
    end

    fprintf(['TotalValveOpen = ' num2str(runInfo.totalValveOpenTime) ' ul\n']);
    close all;
end
