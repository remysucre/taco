#include "taco/io/mtx_file_format.h"

#include <iostream>
#include <sstream>
#include <cstdlib>

#include "taco/tensor_base.h"
#include "taco/util/error.h"

namespace taco {
namespace io {
namespace mtx {

void readFile(std::ifstream &mtxfile, int blockSize,
              int* nrow, int* ncol, int* nnzero,
              TensorBase* tensor) {

  std::string line;
  int rowind,colind;
  double value;
  std::string val;
  while(std::getline(mtxfile,line)) {
    std::stringstream iss(line);
    char firstChar;
    iss >> firstChar;
    // Skip comments
    if (firstChar != '%') {
      iss.clear();
      iss.str(line);
      iss >> *nrow >> *ncol >> *nnzero;
      break;
    }
  }

  if (blockSize == 1) {
    while(std::getline(mtxfile,line)) {
      std::stringstream iss(line);
      iss >> rowind >> colind >> val;
      value = std::stod(val);
      tensor->insert({rowind-1,colind-1},value);
    }
  }
  else {
    while(std::getline(mtxfile,line)) {
      std::stringstream iss(line);
      iss >> rowind >> colind >> val;
      value = std::stod(val);
      tensor->insert({(rowind-1)/blockSize, (colind-1)/blockSize,
        (rowind-1)%blockSize, (colind-1)%blockSize},value);
    }
  }

  tensor->pack();
}

void writeFile(std::ofstream &mtxfile, std::string name,
               const std::vector<int> dimensions, int nnzero) {
  mtxfile << "%-----------------------------------" << std::endl;
  mtxfile << "% MTX matrix file generated by taco " << std::endl;
  mtxfile << "% name: " << name << std::endl;
  mtxfile << "%-----------------------------------" << std::endl;
  for (size_t i=0; i<dimensions.size(); i++) {
    mtxfile << dimensions[i] << " " ;
  }
  mtxfile << " " << nnzero << std::endl;
}


}}}
