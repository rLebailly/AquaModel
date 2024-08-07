# Run SDM

TIME1 <- Sys.time()
# PACKAGES ----------------------------------------------------------------
### LOADED FROM SOURCE CODE FOR THE FUNCTIONS
library(mgcv) # Run the GAM
library(sp) # Spatial data manipulation (reverse geocoding)
library(rworldmap) # Idem
library(raster)
library(rfishbase)

setwd("C:/Users/User/Desktop/Internship/Data")# Download and load data (!!! LOCAL ADRESS)
source("C:/Users/User/Documents/GitHub/AquaModel/Functions.R") # Allows to access the functions (!!! LOCAL ADRESS)


# DATA IMPORTATION --------------------------------------------------------

# Import data borders and coastlines
world <- ne_countries(scale = "medium", returnclass = "sf") # Borders of the countries
world <- world[world$continent != "Antarctica", ] # Erase Antartica (issues with intersect function and useless)
world <-  world %>% # Sort by alphabetical order (except Åland which will be last, DO NOT DO sort(regions), not the same alphabetical order than arrange())
  arrange(by = name)
world_vect <- vect(world)
regions <- world$name

world2 <- readRDS("world_borders_with_buffer.rds") # Import countries with buffered coasts
world_vect2 <- vect(world2) # As vector


#### ENVIRONMENTAL DATA ####
## Download
pathbio <- "C:/Users/User/Desktop/Internship/Data/Climate/bio"
path_bio <- paste0(pathbio,"/wc2.1_30s_bio") # Make a loop in the future for the different files
raster_bio <- list.files(path_bio, pattern = "\\.tif$", full.names = TRUE) # Can't open this list of files ??
bio <- rast(raster_bio) # 19 variables 

## Download every environmental variable for aquatic env
dir <- "C:/Users/User/Desktop/Internship/Data/Climate/aqua"
# layers <- download_layers(dataset_id, variables, constraints, fmt = "csv", directory = dir) # fmt is the format, can also be a raster
NO3 <- rast(paste0(dir,"/no3_baseline_2000_2018_depthsurf_8486_b388_df7c_U1716440129770.nc"))
PO4 <- rast(paste0(dir,"/po4_baseline_2000_2018_depthsurf_6006_d51b_00e9_U1716440256420.nc"))
SI <- rast(paste0(dir,"/si_baseline_2000_2018_depthsurf_395f_f84b_becc_U1716440390984.nc"))
bathy <- rast(paste0(dir,"/terrain_characteristics_bea1_f9a7_03c1_U1716440607679.nc"))
surftemp <- rast(paste0(dir,"/thetao_baseline_2000_2019_depthsurf_74ff_39fa_9adc_U1716440102349.nc"))
prim_prod <- rast(paste0(dir,"/phyc_baseline_2000_2020_depthsurf_7d39_02af_cdbd_U1716500021103.nc"))
# List of variables
env_var <- list(NO3, PO4, SI, bathy, surftemp, prim_prod)
bio_names <- c("tmean_ann", "diurn_mean_range", "isotherm","temp_seas", "tmax", "tmin", "tmean_ann_range",
               "tmin_wet_quart", "tmin_fry_quart", "tmin_warm_quart", "tmin_cold_quart", "prec_ann", "prec_wet",
               "prec_dry", "prec_var", "prec_wet_quart", "prec_dry_quart", "prec_warm_quart", "prec_cold_quart")
names(bio) <- bio_names
bio_list <- lapply(1:nlyr(bio), function(i) bio[[i]])
env_var <- c(env_var, bio_list) # Add the extracted and renamed layers
rm(bio_list, bio)
gc()
rm(NO3, PO4, SI, bathy, surftemp, prim_prod) ; gc() # Remove unused raster

# Set base object # Not cropping before!!
# BASE <- env_var[[19]] # Fine grid (terrestrial raster)
BASE <- env_var[[1]] # Coarser grid (aquatic raster)


#### SPECIES DATA ####
bg_df <- read_rds("GBIF_Fishbase_60.rds") # All GBIF data after 1960 (6,281 species)
# Access rfishbase data to retrieve fishbase aquaculture species names
status <- c('commercial', 'experimental', 'likely future use') # Change if we want different status
sp_fb <- fb_tbl("species") %>% 
  mutate(species = paste(Genus, Species)) %>% 
  tidyterra::select(species, UsedforAquaculture) %>% 
  tidyterra::filter(UsedforAquaculture %in% status) %>% 
  tidyterra::rename(Aquaculture_status = UsedforAquaculture)
# 449 species names for different aquaculture status

# Join species occurrences with aquaculture status
bg_df <- bg_df %>% 
  left_join(sp_fb, by = "species")
rm(sp_fb) ; gc()
bg_df <- distinct(bg_df)


# DATA PREPARATION ---------------------------------------------------------------

#### SPECIES DATA ####
# Reverse Geolocation (get country from coordinates)
points <- data_frame('x' = bg_df$x, 'y' = bg_df$y) # Dataframe with all coordinates from bg_df
bg_df$country <- coords2country(points, world2) # 43.85186 % is NA values ; 59.24157%

aquaspecies_df <- na.omit(bg_df) # Create dataframe with all aquaculture species data
bg_df <- bg_df[!is.na(bg_df$country),] # Remove the rows with NA countries in bg_df

# Select subset of the targeted country for aquaculture species
OCC <- 5 # Set threshold number of minimal occurrences 
aq_df_occ <- aquaspecies_df %>% # Get species occurrences for all countries (> threshold)
  group_by(species) %>%
  tidyterra::filter(n() >= OCC) %>% 
  ungroup()

# list_species <- unique(aq_df_occ$species) # Get the list of species remaining after cleaning

occ_aft_grdft <- readRDS("summary_occurrences_grid_fit.rds") # Occurrences after grid fitting

## ! Get the list of species in aquaculture we want to study, from occ_aft_grdft dataframe 
# Exclude species under 10 occurrences

a <- which(occ_aft_grdft$count_occ_aqua >= 10) # Select Species data that have at least 10 points
occ_aft_grdft <- occ_aft_grdft[a,]
b <- which(occ_aft_grdft$count_occ_bg >= 10*occ_aft_grdft$count_occ_aqua) # Select species that have at least 10 times the number of points for the background point
occ_aft_grdft <- occ_aft_grdft[b,]
list_species <- unique(occ_aft_grdft$species)
rm(a,b)
# length(list_species)

# We end up with only 18 species that can be used in the SDM under the conditions that they have at least
# 10 occurrence points AND 10 times this number for the background species points

# Prepare Model Data for 1 species 
# Aquaculture data
SPECIES <-  list_species[1]
aq_df_sp <- aq_df_occ %>% 
  tidyterra::filter(species == SPECIES) # Filter only the species of interest
aq_df_sp$PA <- 1 # Add presence absence column
# Background data
spbg <- sample_background(background_df = bg_df, sp = SPECIES) # Select subdataframe of random background species where targeted aquaculture species occur
spbg$PA <- 0 


#### ENVIRONMENTAL DATA ####
# Get Countries where species occurr
countries_filtered <- unique(bg_df$country[bg_df$species == SPECIES])
# Crop to list of countries where species occur
env_crop <- lapply(X = countries_filtered, FUN = function(X){ 
  GetCroppedRaster(list_raster = env_var, extent = X) 
})
# Resample and get dataframe
env_rs <- vector("list",length = length(env_crop)) # Create empty list of length = number of countries
for (j in seq_along(env_crop)) { # Resample ; j is the country number
  for(k in seq_along(env_crop[[1]])){ # k is the variable number
    env_rs[[j]][[k]] <- resample(env_crop[[j]][[k]], BASE, "bilinear") # OK  
    # env_rs[[j]][[k]] <- crop(env_rs[[j]][[k]], env_crop[[j]][[1]]) # Re-crop to delete some useless NAs
    env_rs[[j]][[k]] <- as.data.frame(env_rs[[j]][[k]], xy = TRUE) # Dataframe 
  }
}
rm(env_crop) ; gc()
# Create empty list of length = number of countries
env_mg <- vector("list", length = length(env_rs))
for (j in seq_along(env_rs)) { # Resample ; j is the country number
  env_mg[[j]] <- GetMerged(df_list = env_rs[[j]], group_size = length(env_rs[[j]]))
}
# all_env <-  list_rbind(env_mg) # Bind everything together
rm(env_rs) ; gc()


env_mg <- lapply(env_mg, function(x) x[[1]]) # Get flat env_mg object

comb_aqua <- lapply(X = env_mg, FUN = function(X){ # Crop to list of countries where species occur
  GetCombinedDf(X, aq_df_sp, BASE) 
})
comb_bg <- lapply(X = env_mg, FUN = function(X){ 
  GetCombinedDf(X, spbg, BASE) 
})

all_aqua <-  list_rbind(comb_aqua) # Bind everything together (to get number of occurrences)
all_bg <-  list_rbind(comb_bg)

# Change back to °C for the worldclim temperature variables (x10 in the original file to decrease file size)
temp <- c("tmean", "tmax", "tmin") ; temp2 <- c("isotherm", "temp_seas")
for(i in seq_along(temp)){
  ind <- grep(temp[i], colnames(all_aqua), value = TRUE)
  all_aqua[ind] <- (all_aqua[ind])/10
  all_bg[ind] <- (all_bg[ind])/10
}
for(j in seq_along(temp2)){
  ind2 <- grep(temp2[j], colnames(all_aqua), value = TRUE)
  all_aqua[ind2] <- (all_aqua[ind2])/100
  all_bg[ind2] <- (all_bg[ind2])/100
}
rm(temp, temp2, ind, ind2)

# FOR THE SDM, KEEP: all_aqua ; all_bg ; env_mg

# TIME2 <- Sys.time()
# print(TIME1 - TIME2)

# MODEL -------------------------------------------------------------------
# Faire un lapply pour le modele avec la liste de dataframes dat[[i]] acces dans la liste des dfs
sim_func <- function(names_x, name_y,dat){
  tmp_sdm <- gam(formula(paste(name_y,"~",paste(names_x,collapse='+'))),family = binomial, data=dat,select = TRUE, method="GCV.Cp")
  return(tmp_sdm)
}
name_y <- "PA"
# names_all <- c("no3_mean", "po4_mean", "si_mean", "bathymetry_max", "thetao_mean", "phyc_mean",
#              "tmean_ann", "diurn_mean_range", "isotherm","temp_seas", "tmax", "tmin", "tmean_ann_range",
#              "tmin_wet_quart", "tmin_fry_quart", "tmin_warm_quart", "tmin_cold_quart", "prec_ann", "prec_wet",
#              "prec_dry", "prec_var", "prec_wet_quart", "prec_dry_quart", "prec_warm_quart", "prec_cold_quart")
# 
# names_x1 <- paste("s(",names_all,",k=5)",sep="")
gc()

all_aqua2 <- all_aqua[!is.na(all_aqua$PA),] # Remove the rows with NA PA in all_aqua
all_bg2 <- all_bg[!is.na(all_bg$PA),] # Same for background species

data_aqua <- GetModelData(data_aqua = all_aqua, data_bg = all_bg)[[1]] # Get dagta cleaned from unused variables
data_bg <- GetModelData(data_aqua = all_aqua, data_bg = all_bg)[[2]] # Same for background data
names_x <- GetModelData(data_aqua = all_aqua, data_bg = all_bg)[[3]] # List of the names to actually use in the formula

names_x1 <- paste("s(",names_x,",k=5)",sep="") # Add the smoothing function




# Do a loop to get all the predictions for the whole list of dataframes
# sdm_obj <- list()
# for (i in seq_along(dat)) {
#   sdm_obj[[i]] <- sim_func(names_x1,name_y, dat[[i]])
# }
# sdm_obj2=sim_func(names_x1,name_y, dat[[3]]) # get back the sdm object
# sdm_obj2


#### PREDICTIONS ####
# Select countries that are considered hunger hotspots (FAO and WFP)
hh <- c("Haiti", "Mali", "Nigeria", "Lebanon", "Sierra Leone", "Burkina Faso", "Chad", "Central African Rep.",
        "Dem. Rep. Congo", "Palestine", "Syria", "Yemen", "Sudan", "Malawi", "Mozambique",
        "Zambia", "Zimbabwe", "Ethiopia", "Somalia", "Myanmar") # 20 countries

world3 <- world2 %>% # Get geometry of these 20 countries in order to make predictions on them after
  tidyterra::filter(name %in% hh)

# Newdat is supposed to be the full coverage of the area of interest (rasters covering the whole area)
NewDat <- readRDS("env_df_pred.rds")

# Apply the predictions on each country in the list (n = 20)



# Loop for predictions
# pred <- list()
# Newpred <- rep(list(Newdat), length(dat))
# for (i in seq_along(sdm_obj)) {
#   pred[[i]] <- predict.gam(sdm_obj[[i]], newdata=Newdat, type = "response") # ADD type = 'response' to have results on 0-1 scale
#   Newpred[[i]]$predictions <- pred[[i]]
# }

# pred2 <- predict.gam(sdm_obj[[1]], newdata=Newdat) # new data would be the environments that you want to extrapolate the model to.
# Newdat$predictions <- pred # Add the predictions to the new data


#### VALIDATION ####
library(proc) # pROC package to estimate AUC of each model



#### PLOT ####

# world_vect <- st_read(system.file("shape/nc.shp", package="sf"))
country_geom <- world[world$name == 'India', ]
reg_ext <- ext(country_geom)

# x11() # Trop Lourd
image <- ggplot(Newpred[[3]]) + # So freaking long to display
  geom_tile(aes(x = x, y = y, fill = predictions)) +
  geom_sf(data = country_geom, fill = NA, color = "black", size = 0.4) +
  scale_fill_viridis_c() +
  labs( x = "Latitude",
        y = "Longitude",
        fill = "Probability of presence")

# coord_sf(xlim = range(env_mg$x), ylim = range(env_mg$y), expand = FALSE) # Ajuster les limites  
# setwd("C:/Users/User/Desktop/Internship/Images")
ggsave("India_3.jpg", image, width = 10, height = 8)
gc()
