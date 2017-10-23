# -*- coding: utf-8 -*-
from __future__ import unicode_literals
import sys, getopt
import matplotlib as mpl
mpl.use('Agg')
from mpl_toolkits.mplot3d import Axes3D
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
import math
import os
import errno
from itertools import islice
from matplotlib.patches import FancyArrowPatch
from mpl_toolkits.mplot3d import proj3d

fileQ = "Qt"

class Arrow3D(FancyArrowPatch):
    def __init__(self, xs, ys, zs, *args, **kwargs):
        FancyArrowPatch.__init__(self, (0,0), (0,0), *args, **kwargs)
        self._verts3d = xs, ys, zs

    def draw(self, renderer):
        xs3d, ys3d, zs3d = self._verts3d
        xs, ys, zs = proj3d.proj_transform(xs3d, ys3d, zs3d, renderer.M)
        self.set_positions((xs[0],ys[0]),(xs[1],ys[1]))
        FancyArrowPatch.draw(self, renderer)

class cd:
 """Context manager for changing the current working directory"""
 def __init__(self, newPath):
  self.newPath = os.path.expanduser(newPath)

 def __enter__(self):
  self.savedPath = os.getcwd()
  os.chdir(self.newPath)

 def __exit__(self, etype, value, traceback):
  os.chdir(self.savedPath)

def make_sure_path_exists(path):
 try:
  os.makedirs(path)
 except OSError as exception:
  if exception.errno != errno.EEXIST:
   raise

def Round_To_n(x, n):
    return round(x, -int(np.floor(np.sign(x) * np.log10(abs(x)))) + n)

def file_len(fname):
	with open(fname) as f:
		i = -1
		for i, l in enumerate(f):
			pass
	return i + 1

def plot_orbit(orbit1, orbit2, orbit3,w, k):
 MAP = 'winter'
 COLOR1 = 'cyan'
 COLOR2 = 'magenta'
 COLOR3 = 'blue'
 COLOR4 = 'black'
 x1, x2, x3 = zip(*orbit1)
 y1, y2, y3 = zip(*orbit2)
 z1, z2, z3 = zip(*orbit3)
 w1, w2, w3 = zip(*w)
 N = len(x1)
 font = {'weight' : 'bold', 'size' : 24}
 fig = plt.figure(figsize=(12,12))
 ax = fig.add_subplot(111, projection='3d')
 ax.set_aspect('equal')
 step = N/50 + 1
 for i in xrange(0,N-1,N/50):
  alphastep = 0.5*math.log10(i+1)/math.log10(2*N)
  ax.plot(x1[i:i+step], x2[i:i+step], x3[i:i+step], color=COLOR1, 
  alpha = 0.25 + alphastep)
  ax.plot(y1[i:i+step], y2[i:i+step], y3[i:i+step], color=COLOR2, 
  alpha = 0.25 + alphastep)
  ax.plot(z1[i:i+step], z2[i:i+step], z3[i:i+step], color=COLOR3, 
  alpha = 0.25 + alphastep)
  ax.plot(w1[i:i+step], w2[i:i+step], w3[i:i+step], color=COLOR4, 
  alpha = 0.25 + alphastep)
 a = Arrow3D([0,k[0]],[0,k[1]],[0,k[2]], mutation_scale=20, lw=3, arrowstyle="-|>", color="k")
 ax.add_artist(a)

 ax.set_xlim(-1,1)
 ax.set_ylim(-1,1)
 ax.set_zlim(-1,1)
 ax.set_title('Time evolution of particle rotation', fontweight='bold', fontsize=24)
 ax.xaxis.set_ticklabels([])
 ax.yaxis.set_ticklabels([])
 ax.zaxis.set_ticklabels([])
 
 a1_patch = mpatches.Patch(color=COLOR1,label=r'$\hat{a}_{1}$')
 a2_patch = mpatches.Patch(color=COLOR2,label=r'$\hat{a}_{2}$')
 a3_patch = mpatches.Patch(color=COLOR3,label=r'$\hat{a}_{3}$')
 w_patch = mpatches.Patch(color=COLOR4,label=r'$\hat{\omega}$')
 plt.legend(handles = [a1_patch, a2_patch, a3_patch, w_patch],prop={'size':24})
 plt.savefig(fileQ + '.png')

def plot_R(R_list,w,Q,k):
 v1 = []
 v2 = []
 v3 = []
 for R1 in R_list: 
	 R = np.asarray(R1).reshape((3,3))
	 RQ = np.dot(R,np.transpose(Q))
	 v1.append(RQ[0,:]*0.25)
	 v2.append(RQ[1,:]*0.5)
	 v3.append(RQ[2,:])
 plot_orbit(v1,v2,v3,w,k)

if __name__ == "__main__":
	inputfile = 'log'
	pth = 'figs'
	argv = sys.argv[1:]
	try:
		opts, args = getopt.getopt(argv,"hl:p:",["log=", "path="])
	except getopt.GetoptError:
		print 'test.py -log <inputfile>'
		sys.exit(2)
	for opt, arg in opts:
		if opt == '-h' or opt == '--help':
			print 'evo.py -log <inputfile>'
			sys.exit()
		elif opt in ("-l", "--log"):
			inputfile = arg
		elif opt in ("-p", "--path"):
			pth = arg
   
	make_sure_path_exists(pth)
	splt = inputfile.split("log")
	fileQ = fileQ + splt[-1]
	numlines = file_len(inputfile) -22

	log = open(inputfile,'r')
	with cd(pth):
		# Set up data lists
		t = []
		R = []
		Qt = []
		w = []

		magtol = 1e-3

		string = log.readlines()[1]
		k = [float(s)*1.25 for s in string.split()[2:5]]
		log.seek(0)

		Q = np.genfromtxt(islice(log,17,20))
		log.seek(0)
		nnn = np.minimum(numlines,24000)
		lines = log.readlines()[-nnn:]
		#  lines = log.readlines()[22:100000]
		#  lines = log.readlines()[39000:40000]

		for line in lines:
			data = line.split("|")
			
			t.append(map(float,data[7].split()))
			R.append(map(float,data[8].split()))
			RR = np.reshape(map(float,data[8].split()),(3,3))
			Qt.append(map(float,data[4].split())-np.dot(RR,Q)[:,2])
			ww = map(float,data[3].split())
			if np.linalg.norm(ww) != 0:
				ww = ww/np.linalg.norm(ww)
			else:
				ww = [0,0,0]
			w.append(ww*1.2)

		log.close()

		plot_R(R,w,Q,k)
