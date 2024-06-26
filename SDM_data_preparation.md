# Preparation of the Data for SDM 


### Variables
- Verify data collinearity: threshold pairwise correlation coefficient value of |r| > .7
- Standardization of the data to a mean of 0 and SD of 1

### 1. Environmental data
- Chosing the right resolution


#### 1.1 Resample

The different layers need to have the same geometry to be projected in the same grid. Therefore, the 'resample' function, of the package 'terra' is used in order to adapt one SpatRaster's geometry to another's. 

```{r}
resample(layer_raw, layer_base, "method")
```
The method will depend on the nature of the variable itself. 
- Nearest neighbor: **Discrete**
- Majority: **Discrete**
- Bilinear: **Continuous**
- Cubic: **Continuous**

        layer.rsp

For the moment, we chose the bilinear method.

**Snap to grid**

Snap to grid is useful to adapt every layer to the same skeleton scaffold. 
Other method if resample() is not used.

```{r}
SnapToGrid <- function(layer){
  df <- as.data.frame(layer,xy=T) # Use the xy dataframe and append the (x,y) values of each cell + index value
  # Resolution
  Dim <- dim(layer) 
  ResX <- Dim[1] # Resolution for x
  ResY <- Dim[2] # Resolution for y 
  DimLayer <- list(ResX, ResY)
  # Extent
  ext <- ext(layer) # Extent for data (terra object)
  xmin <- ext$xmin
  ymin <- ext$ymin
  xmax <- ext$xmax
  ymax <- ext$ymax
  ext.layer <- list(xmin, ymin, xmax, ymax)
  #Delta
  deltaX <- (xmax - xmin)/ResX
  deltaY <- (ymax - ymin)/ResY 
  # Create grid
  df$snapX <- as.integer(((df$x-xmin)/deltaX) + 0.5)
  df$snapY <- as.integer(((df$y-ymin)/deltaY) + 0.5)
  len <- dim(df)
  df$index <- seq(1,len[1])
  # Return
  return(df)
  # list(df, DimLayer, ext.layer)
}
```

        layer.stg (or final.df)


#### 1.2 Mean value

The a fine time scale isn't relevant in our case. The values per month are not interesting, so we compute the mean and replace the raw data by a mean value column into the new dataset. 

```{r}
mean.df <- function(layer, arg){
  name.col <- paste0("mean_", arg)
  # Calculate mean value per row 
  sub.df.mean1 <-  layer %>%
    mutate(name.col =  rowMeans(dplyr::select(., contains(arg)), na.rm = FALSE)) 
  # Subset without raw data
  sub.df.mean2 <- sub.df.mean1 %>%
    dplyr::select(., -contains(arg))
  # Rename column
  names(sub.df.mean2)[names(sub.df.mean2) == 'name.col'] <- toString(name.col)
  # Final df
  return(sub.df.mean2)
}
```
        layer.mn

#### 1.3 Merge dataframes

When the geometry is right for every layer and the mean value is calculated, we want to merge the datasets in order to have all variables in the same space.

```{r}
new.df <- df1 %>%
  left_joint(df2)
```
*use the dplyr package*. The common columns are x and y.
No matter if x and y are different, anyways will be better organized thanks to snap to grid function.

        layer.mg


#### 1.4 Plot the layers

To check if it works, we need to have a visual representation of the final dataframe. 

**Remark: downloading the data per country for the borders takes a lot of time, maybe try for all of them at once?**

### 2. Species data

#### 2.1 Clean the data
Cleaning the data allows to have a dataset without irrelevant values. 
For that, we use the package 'CoordinateCleaner'. 

```{r}
Getflag <- function(data){
  # Replace alpha-2 with alpha-3
  indices <- match(data$countryCode, countcode$a2)
  data$countryCode <- countcode$a3[indices]
  # Flags
  flags <- clean_coordinates(x = data, 
                                lon = "decimalLongitude", 
                                lat = "decimalLatitude",
                                countries = "countryCode",
                                species = "species",
                                tests = c("countries"))
  return(flags)
}
```

### 3. Merge data
When the environmental and species dataframes are ready, we can merge them. 

```{r}
Final.df <- function(final, sp){
  coord <- matrix(c(sp$x, sp$y), ncol = 2) # Coordinates from species df
  s <- cellFromXY(temp.min, xy = coord)
  p <- which(!is.na(s))
  s1 <- s[p]
  final$species <- NA
  final$species[s1] <- sp$species[p]
  return(final)
}
```
    finaldf

And we can plot by converting it into a Spatraster. 


**Species data**
- Grid variables (linking environmental data and species data with the same projection):
    - Removing records without all the data of each variables
    - Removing cells with multiple occurrences
    - Standardized cleaning with ‘CoordinateCleaner’ package (*removed any records with equal or zero/zero coordinates, found in urban areas, near biodiversity institutions, outside of their listed country, or at the centroids of countries and its subdivisions*)
    - Selection of the data within the time period of interest
- Classification of species occurrences by species type (criteria depending on the contex of the study) and at the chosen point of view and scale (absolute distance, habitat) = ranges
- Remove points with not enough occurrences to avoid overfitting


**Background environment selection**
Fitting of the model with presence background data -> find an adapted method here. Allows to know if there is an overfitting or not. (Generalizable / transferable SDM) --> cf. paper when we are at this part
- ‘target-group background’ approach to select the background sites (?)


At first, need to download the data from fishbase to have the names of the species we want to focus on. We use the 30,000 entries as a baseline for the background and later filter by aquaculture status to run into the SDM. 

```{r}
# Background data 
bg <- fb_tbl("species")
bg$namesp <- paste(bg$Genus, bg$Species, sep = " ")


# saveRDS(bg, file = "fishbase.rds")

summary(bg)
dim(bg)
unique(bg$UsedforAquaculture) # Indication on what's used and what has potential
fish_sp <- bg$namesp # Vector with species names for all fishes
distrifish <- rgbif::occ_data(scientificName = fish_sp)

saveRDS(distrifish, file = "fishbase.rds") # Save GBIF data to save time

```



**Modelling Species Distribution**
Here, two modelling approaches, but depends on the context. --> Cf. paper

    Know what model to use before preparing the data??

--> see the rest later.

Importing the aquaculture species 
```{r}
bg_aqua <- bg %>%
  tidyterra::filter(UsedforAquaculture == "commercial")
dim(bg_aqua) # 358 entries
# Add column with both genus and species name
bg_aqua$namesp <- paste(bg_aqua$Genus, bg_aqua$Species, sep = " ")
unique(bg_aqua$namesp)
# Retrieve this as a vector
aq_sp <- bg_aqua$namesp
# Import distribution data for this list of species (GBIF or FishBase?)
dist_aqua <- rgbif::occ_data(scientificName = aq_sp)
saveRDS(dist_aqua, file = "aquafish.rds")
```
Here, 357 species under the label "commercial" have been imported according to the "used in aquaculture" variable.


Now, I need to combine all of the species into one dataframe. Instead of having a column for each species, we'll have a column 'species' with multiple times the locations where we find the species, so that the dimensions are smaller than the previous method. 



# References
Nguyen & Leung, 2022


# List of things to do

Raph: 
- 
- Look for freshwater environmental data. Lakes and rivers. 
- *How to handle different water bodies* * --> 2 options. 1. differentiate the water bodies OR 2. apply filters. How to overlay environmental variable and physical structures (Lakes) 
- Apply some sort of buffer to handle coastal species. Keep species occurrences from 22kms from the coast (~ 7 cells). Only for borders touching the sea and not the land.


Maia:
- What's done in aquaculture concerning lakes
- Nutrition --> establish a scaling per fish and per nutrient

Overall --> link / quantify fish with needs. 

Ideas: 
- Estimate areas where species can live > a threshold, count the nb of cells that represents and translate in terms of area covered. => 1rst step to estimate a "quantity" or "how much" a species can be grown in a country. 
- 

Keep in mind (project and report prospects)
- The resolution influences the predictive performance of a SDM. The link isn't proportional, which highliths the presence of an optimum. Depends on the species. (Lowen, 2016)
- Definition of pseudoabsences and why they are useful. 1. Assess a better model with more accurate coefficients (look into details to be sure) 2. Assess the differences of sampling effort over all area of distribution. 

Questions:
- What about GBIF data that covers 1873-2019 (with species data way more important in 1960's - 1980's)
- How to quantify fish depending on needs and how geographic data is interesting to implement concretely?



![alt text](image.png)


# Get coastal data

```{r}
# Installer et charger les packages nécessaires
install.packages("rnaturalearth")
install.packages("sf")
install.packages("terra")
install.packages("dplyr")

library(rnaturalearth)
library(sf)
library(terra)
library(dplyr)

# Télécharger les données des pays et des côtes
world <- ne_countries(scale = "medium", returnclass = "sf")
coastline <- ne_download(scale = "medium", type = "coastline", category = "physical", returnclass = "sf")

# Convertir en SpatVecteur de terra
world_vect <- vect(world)
coastline_vect <- vect(coastline)

# Convertir en sf pour les opérations géospatiales
world <- st_as_sf(world)
coastline <- st_as_sf(coastline)

# Créer un buffer autour des côtes pour capturer les frontières côtières
coastline_buffer <- st_buffer(coastline, dist = 0.01)

# Intersecter les pays avec le buffer des côtes pour obtenir les frontières côtières
coastal_boundaries <- st_intersection(world, coastline_buffer)

# Extraire les frontières terrestres en soustrayant les frontières côtières des frontières totales
land_boundaries <- st_difference(world, coastline_buffer)

# Convertir les résultats en SpatVecteur de terra
coastal_boundaries_vect <- vect(coastal_boundaries)
land_boundaries_vect <- vect(land_boundaries)

# Visualiser les pays avec leurs frontières côtières et terrestres
plot(world_vect, col = "gray")
lines(coastal_boundaries_vect, col = "blue", lwd = 2)
lines(land_boundaries_vect, col = "green", lwd = 2)

# Appliquer un buffer uniquement aux frontières côtières
coastal_buffer <- st_buffer(coastal_boundaries, dist = 0.01)
coastal_buffer_vect <- vect(coastal_buffer)

# Visualiser le buffer appliqué aux frontières côtières
plot(world_vect, col = "gray")
lines(coastal_boundaries_vect, col = "blue", lwd = 2)
lines(land_boundaries_vect, col = "green", lwd = 2)
plot(coastal_buffer_vect, col = "red", add = TRUE, alpha = 0.5)

# coastal_buffer_vect est maintenant un SpatVecteur avec le buffer appliqué aux frontières côtières

```
