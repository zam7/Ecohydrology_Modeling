# Ecohydrology 2018
# In Class Assignment 7

setwd("~/github/Ecohydrology_Modeling")

# Load "EcoHydRology" Package
library(EcoHydRology)

#Step 1: Read in daily temperature data, convert to SI, add a date field
MetData <- read.csv("GameFarmRd_1950-present.csv")
MetData$Precip_mm = MetData$Precip*25.4
MetData$Tmax_C = 5/9*(MetData$Tmax-32)
MetData$Tmin_C = 5/9*(MetData$Tmin-32)
MetData$Date = as.Date(ISOdate(MetData$Year, MetData$Month, MetData$Day))

#Step 2: Calculate average daily temperature for each record
MetData$Tavg_C = (MetData$Tmax_C + MetData$Tmin_C)/2

#Step 3: Run snowmelt model with default parameters
lat_deg_Ith = 42.44 #decimal degrees
lat_rad_Ith<-lat_deg_Ith*pi/180 ## latitude in radians
SnowMelt = SnowMelt(MetData$Date, MetData$Precip_mm, MetData$Tmax_C, MetData$Tmin_C, lat_rad_Ith)

#Step 4: Hydrologic watershed model input = precipitation as rain (mm) + snowmelt (mm)
SnowMelt$Precip_eff_mm = SnowMelt$Rain_mm + SnowMelt$SnowMelt_mm # this takes the precip as rain and the snowmelt to find the 
                                                                # effective precipitation as water on land

#Step5: Run Lumped VSA model
#?Lumped_VSA_Mmodel 
Lumped_VSA_Model <- Lumped_VSA_model(dateSeries = SnowMelt$Date, 	P = SnowMelt$Precip_eff_mm, 
                            Tmax = SnowMelt$MaxT_C, Tmin = SnowMelt$MinT_C, latitudeDegrees = lat_deg_Ith, 
                            Tp = 5, Depth = 2010, SATper = 0.27, AWCper = 0.13, StartCond = "wet")

# Tp: time to peak is how quickly water is turned to runoff
# Will run a sensitivity model on: albedo, PETcap, rec_coef, Se_min, C1, Ia_coef

Five_SnowMelt = SnowMelt[(1:(365*5)),]
Five_LVSAM = Lumped_VSA_Model[(1:(365*5)),]

#Step 6: Plot 5 years of Soil Water, Groundwater Storage (Se), and Discharge
par(mfrow=c(5,1))
par(mar=c(0.5,0.5,0.5,0.5))
plot(Five_LVSAM$Date, Five_SnowMelt$Precip_eff_mm, type = "l", ylab = "Precipitation (mm)")
plot(Five_LVSAM$Date, Five_SnowMelt$SnowWaterEq_mm, type = "l", ylab = "SWE (mm)")
plot(Five_LVSAM$Date,Five_LVSAM$SoilWater, type = "l", ylab = "Soil Moisture, AET")
plot(Five_LVSAM$Date,Five_LVSAM$Se, type = "l", ylab = "Groundwater Storage (Se)")
plot(Five_LVSAM$Date,Five_LVSAM$totQ, type = "l", ylab = "Streamflow")

#Discussion questions
# - We are chaining together different models with different assumptions and therefore error, do water balance errors tend to grow without bounds? Why or why not?

# - We started off with a poor assumption about the catchment water storage, why doesn't this seem to matter? 

# - ET is a function of soil water and PET, but PETc (week 5) was a function of plant growth stage, which should also be a function of soil moisture.
#       We're missing an obvious feedback between soil water and plant growth, but we're not modeling this. How does this limit our predictions?
#       What else does our simple model neglect about plant growth?

#Step 7: First order sensitivity on model "calibration" parameters, choose a metric related to whatever you want

# Step 7a: Look up the EcohydRology package ?Lumped_VSA_Mmodel and read about the parameter meanings
# Decide which parameters of the snowmelt model and lumped_vsa_model are best described as calibration parameters

# Define the parameter range
# Initial abstraction (Ia) - hypothesized as sensitive
Iamax = 0.2
Iamin = 0.05
# Forest cover (Fc) - hypothesized as sensitive
fcmax = 1
fcmin = 0
# Storage (Se) - hypothesized as sensitive
Semax = 150
Semin = 50
# Percent Impervious (PI) - hypothesized as sensitive
PImax = 50
PImin = 0
# Wind speed (u) - hypothesized as unsensitive
umax = 5 #m/s
umin = 0 #m/s

# Step 7b: Choose reasonable ranges for parameter values, perform a Monte Carlo sensitivity
# Choose one metric:
# - ratio of ET to Q
# - peak annual streamflow (flooding) # CHOSEN
# - peak annual overland flow (water quality / runoff)
# - number of days stream discharge < 5 mm/day (drinking water drought)
# - number of days soil water below 180 mm (agricultural drought)

n_runs = 100
# Create random distribution of uniformly distributed of parameters
Ia_rand = runif(n_runs, min = Iamin, max = Iamax)
u_rand = runif(n_runs, min = umin, max = umax)
fc_rand = runif(n_runs, min = fcmin, max = fcmax)
Se_rand = runif(n_runs, min = Semin, max = Semax)
PI_rand = runif(n_runs, min = PImin, max = PImax)

Results = data.frame(matrix(nrow = n_runs, ncol = 0))

for (i in 1:n_runs)
{
  snow = SnowMelt(MetData$Date[1:(365*2)], MetData$Precip_mm[1:(365*2)], MetData$Tmax_C[1:(365*2)], 
                  MetData$Tmin_C[1:(365*2)], lat_rad_Ith, windSp = u_rand[i], forest = fc_rand[i])
  
  Precip_eff_mm = snow$Rain_mm + snow$SnowMelt_mm
  
  Lumped_VSA = Lumped_VSA_model(dateSeries = snow$Date, P = Precip_eff_mm, 
                                        Tmax = snow$MaxT_C, Tmin = snow$MinT_C, latitudeDegrees = lat_deg_Ith, 
                                        Tp = 5, Depth = 2010, SATper = 0.27, AWCper = 0.13, StartCond = "wet", 
                                        Se_min = Se_rand[i], Ia_coef = Ia_rand[i], percentImpervious = PI_rand[i])
  
  # store the randomized variables
  Results$windSp_mps[i] = u_rand[i]
  Results$forest_cover[i] = fc_rand[i]
  Results$Ia[i] = Ia_rand[i]
  Results$storage_mm[i] = Se_rand[i]
  Results$PI_percent[i] = PI_rand[i]
  
  # store desired outputs
  Results$modeled_flow_mm[i] = max(Lumped_VSA$modeled_flow)
}

par(mfrow=c(2,3))
par(mar=c(2.5,2.5,2.5,2.5))
plot(Results$windSp_mps, Results$modeled_flow_mm, xlab = "Wind speed (m/s)", ylab = "Runoff (mm)")
plot(Results$forest_cover, Results$modeled_flow_mm, xlab = "Forest cover", ylab = "Runoff (mm)")
plot(Results$Ia, Results$modeled_flow_mm, xlab = "Initial abstraction", ylab = "Runoff (mm)")
plot(Results$storage_mm, Results$modeled_flow_mm, xlab = "Storage", ylab = "Runoff (mm)")
plot(Results$PI_percent, Results$modeled_flow_mm, xlab = "Percent Impervious", ylab = "Runoff (mm)")

#Step 8: Compute Nash Sutcliffe Model Efficiency

# Get data for Fall Creek to use as "observed" values
NS_FC_obs = get_usgs_gage(flowgage_id = "04234000", begin_date = "1950-01-01", end_date="2016-12-31")
NS_FC_obs$flowrate_mmperd = NS_FC_obs$flowdata$flow / (NS_FC_obs$area*1000) # flow is given in cubic meters per day, so we convert to mm/day

# Use VSA model with default inputs for "simulated" values
NS_FC_sim <- Lumped_VSA_Model

# Create an empty matrix to be populated with values for NSE equation
AllData = data.frame(matrix(nrow = 24472, ncol = 0))

AllData$sim_obs = NS_FC_sim$modeled_flow - NS_FC_obs$flowrate_mmperd
NSE_numerator = sum(AllData$sim_obs * AllData$sim_obs)
AllData$obs_obs = NS_FC_obs$flowrate_mmperd - mean(NS_FC_obs$flowrate_mmperd)
NSE_denom = sum(AllData$obs_obs * AllData$obs_obs)

NSE = 1 - (NSE_numerator/NSE_denom)
# result is NSE = 0.5234

