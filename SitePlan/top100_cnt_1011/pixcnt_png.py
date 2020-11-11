# -*- coding: utf-8 -*-
"""
Created on Mon Oct  5 17:51:24 2020

@author: ggne0447
"""
#!/usr/bin/env python

# Install OpenCV and numpy
# $ pip install opencv-python numpy

import cv2
import numpy as np
import os
import csv

def nothing(x):
  pass
thisdir = os.getcwd()
fileType = ".PNG" # ".bil"
#1.read img files
# r=root, d=directories, f = files
c = 0
with open('innovators1.csv', 'w', newline='') as fileC:
    writer = csv.writer(fileC)
    writer.writerow(["SN", "Name", "64-QAM%","256-QAM%"])
    for r, d, f in os.walk(thisdir):
        for file in f:
            if file.endswith(fileType):
              fileList= os.path.join(r, file)
              print(fileList)        
              img = cv2.imread(fileList)
              #cv2.namedWindow('image')
              # cv2.createTrackbar('min','image',0,255,nothing)
              # cv2.createTrackbar('max','image',0,255,nothing)
              # get dimensions of image
              dimensions = img.shape
              # height, width, number of channels in image
              height = img.shape[0]
              width = img.shape[1]
              channels = img.shape[2]
              #print(img[500:510,800:810])
              #print('Image Dimension    : ',dimensions)
              #print('Image Height       : ',height)
              #print('Image Width        : ',width)
              #print('Number of Channels : ',channels)
              # while(1):
              #2.Setup match filter
              RED_MIN = np.array([20,20,185], np.uint8)
              # maximum value of brown pixel in BGR order -> brown
              RED_MAX = np.array([100, 100, 255], np.uint8)
              GREEN_MIN = np.array([20,185,20], np.uint8)
              # maximum value of brown pixel in BGR order -> brown
              GREEN_MAX = np.array([95, 255,100], np.uint8)
              #3.Filter
              red = cv2.inRange(img, RED_MIN, RED_MAX)
              green = cv2.inRange(img, GREEN_MIN, GREEN_MAX)
              no_red = cv2.countNonZero(red)
              no_green = cv2.countNonZero(green)
              #print(no_red)
              #print(no_green)
              perred = 100*no_red/(height*width)
              pergreen = 100*no_green/(height*width)
              #print('The number of Red pixels is: ' + str(no_red))
              #print('The number of Green pixels is: ' + str(no_green))
              c=c+1
              #4. Results
              print(c)
              print('%256QAM ' + str(pergreen)+ '%')
              print('%64QAM ' + str(perred)+ '%')
              #4a store res {CSV}
              writer.writerow([c, fileList, perred,pergreen])
               
              #cv2.namedWindow("opencv")
              #cv2.imshow("opencv",img)
              #cv2.waitKey(0)
# # vim: ft=python ts=4 sw=4 expandtab