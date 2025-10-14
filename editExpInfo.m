% Editting expInfo structures

%% Load expInfo
path = '\\znas.cortexlab.net\Code\Rigging\ExpDefinitions\Jacob\vr_envs';
file_name = 'expInfo_base.mat';

load(fullfile(path, file_name));

%% Blank out fields

expInfo.animalName = [];
expInfo.sessionName = [];
expInfo.dateStr = [];
expInfo.expRef = [];
expInfo.LocalDir = [];
expInfo.ServerDir = [];
expInfo.AnimalDir = [];
expInfo.SESSION_NAME = [];
expInfo.animalLogName = [];

%% Edit reward contingecies

% Move reward to grating location
gratingsPos = 175;
expInfo.rewardPosition(:) = gratingsPos;

% Only rewards for particular orientations
rewarded90 = true;
env90Str = '90';
rewardOffset = 50;

if rewarded90
    rewardedEnvsMask = find(contains(expInfo.envNames, env90Str),2);
    rewardedTrialsMask = ismember(expInfo.envIndex,rewardedEnvsMask);
    
    expInfo.rewardPosition(rewardedTrialsMask) = ...
        expInfo.roomLength(1) + rewardOffset;
else
    rewardedEnvsMask = find(~contains(expInfo.envNames, env90Str),2);
    rewardedTrialsMask = ismember(expInfo.envIndex,rewardedEnvsMask);
    
    expInfo.rewardPosition(rewardedTrialsMask) = ...
        expInfo.roomLength + rewardOffset;
end

%% save expInfo

out_name = 'expInfo_custom.mat';
save(fullfile(path, out_name), 'expInfo')