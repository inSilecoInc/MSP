###########################################################################################
###########################################################################################
### 
### This code is a recreation in R of ImportantHabitat.py by Anna Serdynska from 2012
### Original purpose:
### "To create important habitat layers for various fish species from DFO's RV survey data"
### 
### Author: Philip Greyson
### Date: December 2019
### 
### Using RV survey data clipped to the Scotian Shelf this process interpolates surfaces of
### standardized catch weight (STDWGT) for six time periods, reclassifies the surfaces into
### deciles, sums the six surfaces together and then creates a summary surface for each 
### species out of the top 20 percent (sum > 48 out of possible 60).
### 
### Skewness and presence metrics are calculated for each species.
### The resultant raster, interpreted as a way of categorizing the persistance of a species
### through different management regimes, is exported.
### 
###########################################################################################
###########################################################################################


library(rgdal) # to read shapefiles
library(raster) # for the various raster functions
library(dplyr) # all-purpose data manipulation (loaded after raster package since both have a select() function)
library(gstat) # for IDW function
library(sp) #Classes and methods for spatial data
library(rgeos) # required for the dissolve argument in rasterToPolygon() according to help file
library(moments) # required for skewness calculation
library(Mar.datawrangling) # required to access RV data
library(maps)
library(ggplotify) # to convert plots to grobs (as.grob function)
library(grid)
library(ggplot2)



# Load RV data
# Network Address
# wd <- "//ent.dfo-mpo.ca/ATLShares/Science/CESD/HES_MSP/R"

# home location
wd <- "C:/BIO/20200306/GIT/R/MSP"
setwd(wd)

# on my home directory I have to go up one dir and across to /data/
data.dir <- "../data/mar.wrangling"
get_data('rv', data.dir = data.dir)

# alternate site for the data:
# data.dir <- "//dcnsbiona01a/BIODataSVC/IN/MSP/Projects/Aquaculture/SearchPEZ/inputs/mar.wrangling"

source("./SpatialDataSynopsis/code/src/fn_SelectAllRVSpatialExtentMkGrid.r")
source("./SpatialDataSynopsis/code/src/fn_InterpolateRV.r")


# using SP package, read in a shapefile
# bring in OceanMask for clipping data and rasters
dsn <- "../data/Boundaries"
oceanMask <- readOGR(dsn,"ScotianShelfOceanMask_WithoutCoastalZone_Edit")
oceanMaskUTM <- spTransform(oceanMask,CRS("+init=epsg:26920"))

# bring in land layer
# land10m <- readOGR(dsn,"ne_10m_land_Clip")
# land10mUTM <- spTransform(oceanMask,CRS("+init=epsg:26920"))
load("../data/Boundaries/land.RData")
# plot(oceanMask, ext = oceanMask)

CRS_ras <- CRS("+init=epsg:4326") # WGS84
save_tables('rv')


# - Make oversize grid ----------------------
grd <- SelectRV_MkGrid_fn("SUMMER", 1, 100000)
restore_tables('rv',clean = FALSE)

# Get list of species from other data table
# fish <- read.csv("./data/Spreadsheets/FifteenSpecies.csv", header = TRUE)
# species <- read.csv("../data/Spreadsheets/ThirtyFiveSpecies.csv", header = TRUE)
species <- read.csv("../data/Spreadsheets/SynopsisSpecies.csv", header = TRUE)
# filter out snow crab.  snow crab was not recorded until 1981
species <- filter(species, CODE != 2526)
speciescode <- unique(species[,1])

# get names and Scinames of species as well
# speciescode <- unique(fish[,1:3])

# Reduce number of species for testing processing
# speciescode <- speciescode[7:9] # pollock, redfish, halibut

# speciescode <- speciescode[7] # Redfish
 speciescode <- speciescode[c(1,22)] # cod and barndoor skate
# speciescode <- speciescode[c(22)] # barndoor skate
# speciescode <- speciescode[c(1)] # cod

#------ Set year variables -----------------
# Single date range
# yearb <- 2014
# yeare <- 2020
# Single date range
# yearb <- 2000
# yeare <- 2020

# All sample years (1970 - 2018)
# yearb <- c(1970, 1978, 1986, 1994, 2007, 2012)
# yeare <- c(1978, 1986, 1994, 2007, 2012, 2019)

# All sample years (2000 - 2019)
yearb <- c(2000, 2005, 2009, 2014)
yeare <- c(2005, 2009, 2014, 2020)
# reduced date range for testing processing
# yearb <- c(1970, 1978)
# yeare <- c(1977, 1985)
#------ END Set year variables -----------------


# ---------- BEGIN Loops ----------------------####

count <- 1
start_time <- Sys.time()
raster_list2 <- list() # create list to hold SUM rasters
raster_list3 <- list() # create list to hold species rasters
skew_listFinal <- list() # create list to hold skewness values
presence_listFinal <- list() # create a list to hold presence values (row counts)
stackRas <- raster(grd)
for(i in 1:length(speciescode)) {
  Time <- 1
  raster_list <- list() # Create an empty list
  skew_list1 <- list() # create list to hold skewness values
  presence_list1 <- list() # create a list to hold presence values (row counts)
  print(paste("Species ", speciescode[i],sep = ""))
  for (y in 1:length(yearb)) {
    yearb1 <- yearb[y]
    yeare1 <- yeare[y]
    Time1 <- paste("T", Time, sep = "")
    print(paste("Loop ",count, "Time ", Time1, sep = ""))
    # filter data
    clip_by_poly(db='rv', clip.poly = oceanMask) # clip data to the extent of the Ocean Mask
    GSMISSIONS <- GSMISSIONS[GSMISSIONS$YEAR >= yearb1 & GSMISSIONS$YEAR < yeare1 & GSMISSIONS$SEASON=="SUMMER",]
    GSXTYPE <- GSXTYPE[GSXTYPE$XTYPE==1,]
    self_filter(keep_nullsets = FALSE,quiet = TRUE) # 659 in GSCAT
    GSINF2 <- GSINF # make copy of GSINF to use for a full set of samples
    GSSPECIES <- GSSPECIES[GSSPECIES$CODE %in% speciescode[i],] # WORKS
    self_filter(keep_nullsets = FALSE,quiet = TRUE)
    print("Completed self-filter")
    # Create a valid DEPTH field (Depth values are in fathoms)
    GSINF2$DEPTH <- round((GSINF2$DMIN*1.8288+GSINF2$DMAX*1.8288)/2,2)
    # Keep only the columns necessary
    # ("MISSION" "SETNO" "SDATE" "STRAT" "DIST" "DEPTH" "BOTTOM_TEMPERATURE" "BOTTOM_SALINITY" "LATITUDE" "LONGITUDE")
    GSINF2 <- dplyr::select(GSINF2,1:3,5,12,24,30:31,33:34)
    # rename some fields
    names(GSINF2)[7:8] <- c("BTEMP","BSAL")
    
    # use a merge() to combine MISSION,SETNO with all species to create a presence/absence table
    SpecOnly <- dplyr::select(GSSPECIES,3)
    # rename 'CODE' to 'SPEC'
    names(SpecOnly)[1] <- c("SPEC")
    
    # this merge() creates a full set of all MISSION/SETNO and SPECIES combinations
    Combined <- merge(GSINF2,SpecOnly)
    GSCAT2 <- dplyr::select(GSCAT,1:3,5:6)
    
    # names(Combined)
    # Merge Combined and GSCAT2 on MISSION and SETNO
    allCatch <- merge(Combined, GSCAT2, all.x=T, by = c("MISSION", "SETNO", "SPEC"))
    # Fill NA records with zero
    allCatch$TOTNO[is.na(allCatch$TOTNO)] <- 0
    allCatch$TOTWGT[is.na(allCatch$TOTWGT)] <- 0
    # Standardize all catch numbers and weights to a distance of 1.75 nm
    allCatch$STDNO <- allCatch$TOTNO*1.75/allCatch$DIST
    allCatch$STDWGT <- allCatch$TOTWGT*1.75/allCatch$DIST
    
    countAllSample <- nrow(allCatch)
    countPresence <- nrow(filter(allCatch,STDWGT > 0))
    
    presence <- paste(Time1, speciescode[i],countAllSample,countPresence,sep=":\t")
    presence_list1[[y]] <- presence
    
    # create spatial object out of allCatch with name of species
    # write to shapefile
    coordinates(allCatch) <- ~LONGITUDE+LATITUDE
    proj4string(allCatch)<- CRS("+init=epsg:4326")
    allCatchUTM<-spTransform(allCatch,CRS("+init=epsg:26920"))
    
    # Export the shapefile - NOTE, this was done to compare with ArcGIS processing
    # print(paste("Loop ",count, " - exporting shapefile",sep = ""))
    
    # Network location
    # dsn = "U:/GIS/Projects/MSP/Persistance/Output/"
    # Home location
    dsn = "./SpatialDataSynopsis/Output"
    
    # writeOGR(allCatchUTM,"./SpatialDataSynopsis/Output",paste(Time1,"SP_",speciescode[i],"_UTM",sep = ""),driver="ESRI Shapefile")
    # writeOGR(allCatchUTM,"./SpatialDataSynopsis/Output",paste("SP_",speciescode[i],"_AllUTM",sep = ""),driver="ESRI Shapefile")
    # writeOGR(allCatchUTM,dsn,paste(Time1,"SP",speciescode[i],"_UTM",sep = ""),driver="ESRI Shapefile", overwrite_layer = TRUE)
    
    # Interpolate the sample data (STDWGT) using the large extent grid
    # Using the same values for Power and Search Radius as Anna's script (idp and maxdist)
    print("Sending data to Grid_fun")
    Gridlist <-  Grid_fn(allCatchUTM, grd, 2.0, 16668)
    print("Grid_fun complete"    )
    rasDD <- projectRaster(Gridlist$raster, crs=CRS_ras) #change test.idw from UTM to wgs84
    dir <- "./SpatialDataSynopsis/Output/"
    # This is the UTM version of the raster
    # For plotting use the WGS84 VERSION
    # Gridlist$raster is the reclassed raster
    # perhaps rename the output of Grid_fn to make that clearer
  
    raster_list[[y]] <- Gridlist$raster
    skew_listFinal[[i]] <- Gridlist$skew
    #raster_list[[y]] <- rasDD
    # why am I creating a stack of the rasters but also adding 
    # each raster to a list
    # AND then adding that list to another list (raster_list3???)
    tmpRas <- Gridlist$raster
    names(tmpRas) <- paste("SP",speciescode[i],"_",Time1,"_IDW",sep = "")
    stackRas <- addLayer(stackRas,tmpRas)
    print("Restoring tables")
    print(paste("stackRas has ",nlayers(stackRas)," layers", sep=""))
    restore_tables('rv',clean = FALSE)
    
    raster_list3 <- append(raster_list3, raster_list)
    Time <- Time + 1
  }
  
  # line for 6 time periods
  #  s <- sum(raster_list[[1]],raster_list[[2]],raster_list[[3]],raster_list[[4]],raster_list[[5]],raster_list[[6]])
  # line for four time periods
  s <- sum(raster_list[[1]],raster_list[[2]],raster_list[[3]],raster_list[[4]], na.rm = TRUE)
  # s2 <- s > 48 # Anna's original value was 39 but I've got another time period so increased it to 48 (80%)
  # s2 <- s > 32 # Top 20% assuming it's broken into 10 classes AND four time periods
  s2 <- s >= 16 # Top 20% assuming it's broken into 5 classes AND four time periods
  
  names(s2) <- paste("SP",speciescode[i],"_TALL_IDW",sep = "")
  stackRas <- addLayer(stackRas,s2)
  
  raster_list2[[i]] <- s2
  skew_listFinal[[i]] <- skew_list1
  presence_listFinal[[i]] <- presence_list1
  count <- count + 1
}
# stackRas <- dropLayer(stackRas,1)
# write.table(as.data.frame(skew_listFinal),"./SpatialDataSynopsis/Output/Skewness.csv",sep=",")
# write.table(as.data.frame(presence_listFinal),"./SpatialDataSynopsis/Output/Presence.csv",sep=",")
# end_time <- Sys.time()
# end_time - start_time
# ---------- END Loops ----------------------####


# Rename each raster in raster_list2 and export as a .tif
start_time <- Sys.time()
for(i in 1:length(speciescode)){
  names(raster_list2[[i]]) <- paste("SP_",speciescode[i],sep = "")
  tif <- paste(dir,names(raster_list2[[i]]),"_SUM.tif",sep = "")
  writeRaster(raster_list2[[i]],tif, overwrite = TRUE)
  # poly <- rasterToPolygons(raster_list2[[i]], fun=function(x){x==1}, n=4, na.rm=TRUE, digits=12, dissolve=TRUE)
  # writeOGR(poly,"U:/GIS/Projects/MSP/HotSpotCode/Output",paste("TestSP_",speciescode[i],sep = ""),driver="ESRI Shapefile", overwrite_layer = TRUE)
}
end_time <- Sys.time()
end_time - start_time

par(mfrow=c(2,4))
plot1 <- site_map(oceanMask,land10m,HexGridDD, raster_list,40) #studyArea,land,hex, IDWraster,buf

# Test of writing tifs from Stack
for(i in 1:nlayers(stackRas)){
  #names(stackRas[[i]]) <- paste("SP_",speciescode[i],sep = "")
  tif <- paste(dir,names(stackRas[[i]]),"_SUM.tif",sep = "")
  writeRaster(stackRas[[i]],tif, overwrite = TRUE,datatype = "INT1U")
}

# Write the entire stack out as a .grd file
writeRaster(stackRas,"./SpatialDataSynopsis/Output/IDWReclassed.grd", format="raster")
# All species
writeRaster(stackRas,"./SpatialDataSynopsis/Output/IDWReclassed_Allsp.grd", format="raster")
RasStack <- stack("./SpatialDataSynopsis/Output/TwoSp_InterpReclass.grd")

# Write it out as a multiband tif
writeRaster(stackRas,"./SpatialDataSynopsis/Output/Multi.tif",format = "GTiff", bylayer = FALSE)


for(i in 1:length(raster_list)){
  names(raster_list[[i]]) <- paste("Reclass2_SP200_","T",i,sep = "")
  rtif <- paste(dir,"SP",speciescode[i],"_rclass_T",Time,".tif",sep = "")
  tif <- paste(dir,names(raster_list[[i]]),".tif",sep = "")
  writeRaster(raster_list[[i]],tif, overwrite = TRUE, datatype = "INT1U")
  # poly <- rasterToPolygons(raster_list2[[i]], fun=function(x){x==1}, n=4, na.rm=TRUE, digits=12, dissolve=TRUE)
  # writeOGR(poly,"U:/GIS/Projects/MSP/HotSpotCode/Output",paste("TestSP_",speciescode[i],sep = ""),driver="ESRI Shapefile", overwrite_layer = TRUE)
}

# Export layers in stackRas to .tif files

for(i in 1:nlayers(stackRas)){
  tif <- paste(dir,names(stackRas[[i]]),".tif",sep = "")
  writeRaster(stackRas[[i]],tif, overwrite = TRUE, datatype = "INT1U")
}

