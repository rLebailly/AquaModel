# 🐟 AquaModel: a model to link aquaculture and nutritional needs in the world 🐟

**Authors: Raphaëlle Lebailly (MSc Graduate at Rennes University) & Prof. Brian Leung (Researcher and Associate Professor at McGill University)**

With this project, we aim to built a Decision Making System for Aquaculture practices. 
The main goal is to link nutritional issues (malnutrition or deficiencies) with species suitable for aquaculture and for the local environment. We would like to make it accessible for everyone, from scientists and researchers to potential aquaculture farmers, eventually. 

 <img src="https://www.globalseafood.org/wp-content/uploads/2018/12/Thai-prawn-farm_SS_1500-1280x959.jpg" align="center" alt="Global Seafood Alliance" width="400" height="300">

Aquaculture is one of the most dynamic and promising food production area (Naylor *et al.*, 2023), which makes it interesting to develop tools for to better master it. 
Futhermore, many species of fishes, crustaceans, molluscs and seaweed (from both seawater and freshwater) contain a lot of micronutrients that a vast majority of people living in the Global South lack.

To do so, we decided to combine a Species Distribution Model (SDM) of the used and potentionally used aquaculture species and the distribution of macronutrients and micronutrients needs. <br />  

**Files:**
- **README.md**: Explains the goal of the project.
- **SDM_data_preparation.md**: Detailed explanations of the methodology.
- **GBIF_Fishbase_60.rds**: GBIF data for the species used in aquaculture after 1960.
- **world_borders_with_buffer.rds**: Object with all countries geometries with a 22km buffer on the coasts.
- **summary_occurrences_grid_fit.rds**: List of species usable for SDM setting up (thresholds after coarse grid fitting).
- **env_df_pred_all.rds**: List of environmental data of the hunger hotspots (countries) selected to project the SDMs. 
- **Functions.r**: Functions to be used in "Run_SDM.r"
- **Run_SDM.r**: Script to run the SDM.
- **LEBAILLY_Raphaëlle_Internship_report_M2.pdf**: Internship report with detailed explanation of the project and useful sources.
 
