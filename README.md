## ElephantEdge
This repository is for a project created at Hackster.io for the ElephantEdge contest. I have created a deep learning model using Edge Impulse Studio to detect elephant activity. For the training 3-axes accelerometer and 3-axes gyroscope data are used. The final model is deployed to the Arduino Nano 33 BLE Sense and the inferencing result is displayed using mobile app over BLE connection. Please read the full story here: [Elephant Activity Deep Learning Model](https://www.hackster.io/naveenbskumar/elephant-activity-deep-learning-model-5b3e98)

## Data Collection
I could not find any elephant activity/motion/orientation data available in the public domain to use freely. I used a Goat Sheep Dataset to train a model which can be downloaded freely from https://easy.dans.knaw.nl/ui/datasets/id/easy-dataset:76131/tab/2 and can be used with citing the following paper:

Jacob W. Kamminga, Helena C. Bisby, Duv V. Le, Nirvana Meratnia, and Paul J.M. Havinga. Generic online animal activity recognition on collar tags. In <i>Proceedings of the 2017 ACM International Joint Conference on Pervasive and Ubiquitous Computing (UbiComp/ISWC’17)</i>. ACM, September 2017

The Jupyter Notebook for accelerometer/gyroscope data filtering and generating files required by Edge Impulse format can be found here: [data_acquisition_acc_gyr.ipynb](data_acquisition_acc_gyr.ipynb)

## Deep Learning Model
The model has 1 input, 1 output and 12 Fully connected (dense) hidden layers.

<img src="images/graph.svg" width="250%">
<img src="images/legend.svg" width="50%">

The model creation and the training Jupyter Notebook can be found here: [ei-elephant_edge_v3-nn-classifier.ipynb](ei-elephant_edge_v3-nn-classifier.ipynb)

## Run inferencing on Arduino Nano 33 BLE Sense

### Install Arduino IDE
Download and install Arduino IDE (1.8.13 or above) from here: [Arduino IDE](https://www.arduino.cc/en/software).

### Clone repository
git clone https://github.com/metanav/ElephantEdge.git

### Download Arduino library 

Download [ei-elephant_edge_v3-arduino-1.0.2.zip](ei-elephant_edge_v3-arduino-1.0.2.zip)  and add this library through the Arduino IDE via:
Sketch > Include Library > Add .ZIP Library...

### Run Demo
Open [sketches/inferencing_demo/inferencing_demo.ino](sketches/inferencing_demo/inferencing_demo.ino) in the Arduino IDE and click on Sketch > Upload.

## Display Inferencing result using Mobile App
The development of mobile app was done on MacOS with iOS target but it can be compiled on other supported platforms and can be deployed to the supported Android devices.
### Install Flutter
Please follow installation instructions here: https://flutter.dev/docs/get-started/install

### Deploy the app
Change directory to the <b>app/</b> inside the downloaded location of the cloned repo and run <b>flutter run --release</b>.
Please see the [demo video](https://www.youtube.com/watch?v=AXcJ5IsnUaw&feature=emb_logo).


