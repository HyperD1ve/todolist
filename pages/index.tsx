import React, { useState, useEffect } from 'react';
import { Trash2, Plus, MoreVertical } from 'lucide-react';
import { db } from '../lib/firebase';
import { collection, getDocs, addDoc, updateDoc, deleteDoc, doc, query, orderBy, serverTimestamp } from 'firebase/firestore';

interface Task {
  id: string;
  title: string;
  description: string;
  urgency: string;
  importance: string;
  completed: boolean;
  position: number;
  createdAt?: any;
}

export default function TaskWidget() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [showNewTask, setShowNewTask] = useState(false);
  const [draggedTask, setDraggedTask] = useState<Task | null>(null);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [loading, setLoading] = useState(true);

  const urgencyColors = {
    red: 'Today',
    orange: 'Tomorrow',
    yellow: 'Day After',
    green: 'This Week',
    blue: 'Later'
  };

  const importanceColors = {
    red: 'Critical',
    orange: 'High',
    yellow: 'Medium',
    green: 'Low'
  };

  useEffect(() => {
    loadTasks();
  }, []);

  const loadTasks = async () => {
    try {
      const tasksRef = collection(db, 'tasks');
      const q = query(tasksRef, orderBy('position', 'asc'));
      const snapshot = await getDocs(q);
      const loadedTasks = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      setTasks(loadedTasks);
    } catch (error) {
      console.error('Error loading tasks:', error);
    } finally {
      setLoading(false);
    }
  };

  const addTask = async (title, description, urgency, importance) => {
    try {
      const tasksRef = collection(db, 'tasks');
      await addDoc(tasksRef, {
        title,
        description,
        urgency,
        importance,
        completed: false,
        position: tasks.filter(t => !t.completed).length,
        createdAt: serverTimestamp()
      });
      await loadTasks();
      setShowNewTask(false);
    } catch (error) {
      console.error('Error adding task:', error);
    }
  };

  const deleteTask = async (id) => {
    try {
      const task = tasks.find(t => t.id === id);
      
      if (task?.completed) {
        await deleteDoc(doc(db, 'tasks', id));
      } else {
        await updateDoc(doc(db, 'tasks', id), { completed: true });
      }
      await loadTasks();
    } catch (error) {
      console.error('Error deleting task:', error);
    }
  };

  const restoreTask = async (id) => {
    try {
      await updateDoc(doc(db, 'tasks', id), { completed: false });
      await loadTasks();
    } catch (error) {
      console.error('Error restoring task:', error);
    }
  };

  const moveTask = async (id, direction) => {
    const activeTasks = tasks.filter(t => !t.completed);
    const completedTasks = tasks.filter(t => t.completed);
    const idx = activeTasks.findIndex(t => t.id === id);

    if (direction === 'up' && idx > 0) {
      [activeTasks[idx], activeTasks[idx - 1]] = [activeTasks[idx - 1], activeTasks[idx]];
    } else if (direction === 'down' && idx < activeTasks.length - 1) {
      [activeTasks[idx], activeTasks[idx + 1]] = [activeTasks[idx + 1], activeTasks[idx]];
    }

    try {
      for (let i = 0; i < activeTasks.length; i++) {
        await updateDoc(doc(db, 'tasks', activeTasks[i].id), { position: i });
      }
      setTasks([...activeTasks, ...completedTasks]);
    } catch (error) {
      console.error('Error moving task:', error);
    }
  };

  const handleDragStart = (task) => {
    setDraggedTask(task);
  };

  const handleDragOver = (e) => {
    e.preventDefault();
  };

  const handleDrop = async (targetTask) => {
    if (!draggedTask || draggedTask.id === targetTask.id) return;

    const activeTasks = tasks.filter(t => !t.completed);
    const completedTasks = tasks.filter(t => t.completed);

    const dragIdx = activeTasks.findIndex(t => t.id === draggedTask.id);
    const targetIdx = activeTasks.findIndex(t => t.id === targetTask.id);

    if (dragIdx !== -1 && targetIdx !== -1) {
      [activeTasks[dragIdx], activeTasks[targetIdx]] = [activeTasks[targetIdx], activeTasks[dragIdx]];
      setTasks([...activeTasks, ...completedTasks]);
      
      try {
        for (let i = 0; i < activeTasks.length; i++) {
          await updateDoc(doc(db, 'tasks', activeTasks[i].id), { position: i });
        }
      } catch (error) {
        console.error('Error updating positions:', error);
      }
    }
    setDraggedTask(null);
  };

  const getColorBg = (color) => {
    const colors = {
      red: 'bg-red-100 border-red-300',
      orange: 'bg-orange-100 border-orange-300',
      yellow: 'bg-yellow-100 border-yellow-300',
      green: 'bg-green-100 border-green-300',
      blue: 'bg-blue-100 border-blue-300'
    };
    return colors[color] || 'bg-gray-100 border-gray-300';
  };

  const getColorDot = (color) => {
    const colors = {
      red: 'bg-red-500',
      orange: 'bg-orange-500',
      yellow: 'bg-yellow-500',
      green: 'bg-green-500',
      blue: 'bg-blue-500'
    };
    return colors[color] || 'bg-gray-500';
  };

  if (loading) {
    return (
      <div className="w-full max-w-md mx-auto p-4 bg-gradient-to-br from-slate-50 to-slate-100 rounded-lg shadow-lg">
        <p className="text-center text-slate-600">Loading...</p>
      </div>
    );
  }

  const activeTasks = tasks.filter(t => !t.completed);
  const completedTasks = tasks.filter(t => t.completed);

  return (
    <div className="w-full max-w-md mx-auto p-4 bg-gradient-to-br from-slate-50 to-slate-100 rounded-lg shadow-lg">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-slate-800 mb-1">My Tasks</h1>
        <p className="text-sm text-slate-600">{activeTasks.length} active • {completedTasks.length} completed</p>
      </div>

      <button
        onClick={() => setShowNewTask(true)}
        className="w-full mb-4 py-2 px-4 bg-blue-500 hover:bg-blue-600 text-white rounded-lg flex items-center justify-center gap-2 transition"
      >
        <Plus size={18} /> New Task
      </button>

      {showNewTask && (
        <NewTaskForm onAdd={addTask} onCancel={() => setShowNewTask(false)} colors={urgencyColors} importanceColors={importanceColors} />
      )}

      <div className="space-y-2 mb-6">
        {activeTasks.map((task, idx) => (
          <div
            key={task.id}
            draggable
            onDragStart={() => handleDragStart(task)}
            onDragOver={handleDragOver}
            onDrop={() => handleDrop(task)}
            className={`p-3 rounded-lg border-2 cursor-move transition ${getColorBg(task.urgency)} hover:shadow-md`}
          >
            <div className="flex items-start gap-3">
              <div className="flex-shrink-0 font-bold text-lg text-slate-700 w-6 text-center">
                {idx + 1}
              </div>
              <div className="flex-grow">
                <h3 className="font-semibold text-slate-800">{task.title}</h3>
                {task.description && <p className="text-sm text-slate-600 mt-1">{task.description}</p>}
                <div className="flex gap-2 mt-2">
                  <span className="text-xs bg-white bg-opacity-60 px-2 py-1 rounded">
                    <span className={`inline-block w-2 h-2 rounded-full ${getColorDot(task.urgency)} mr-1`}></span>
                    {urgencyColors[task.urgency]}
                  </span>
                  <span className="text-xs bg-white bg-opacity-60 px-2 py-1 rounded">
                    <span className={`inline-block w-2 h-2 rounded-full ${getColorDot(task.importance)} mr-1`}></span>
                    {importanceColors[task.importance]}
                  </span>
                </div>
              </div>
              <div className="flex flex-col gap-1">
                <button onClick={() => moveTask(task.id, 'up')} className="text-slate-600 hover:text-slate-800 text-xs px-2 py-1 bg-white rounded">↑</button>
                <button onClick={() => moveTask(task.id, 'down')} className="text-slate-600 hover:text-slate-800 text-xs px-2 py-1 bg-white rounded">↓</button>
                <button onClick={() => { setSelectedTask(task); setShowDetails(true); }} className="text-slate-600 hover:text-slate-800 p-1 bg-white rounded"><MoreVertical size={16} /></button>
                <button onClick={() => deleteTask(task.id)} className="text-red-600 hover:text-red-800 p-1 bg-white rounded"><Trash2 size={16} /></button>
              </div>
            </div>
          </div>
        ))}
      </div>

      {completedTasks.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold text-slate-700 mb-2 px-1">Completed Tasks</h2>
          <div className="space-y-2 bg-slate-200 bg-opacity-30 p-2 rounded-lg">
            {completedTasks.map((task) => (
              <div key={task.id} className="p-2 bg-white rounded-lg border border-slate-300 flex items-center justify-between">
                <div className="flex-grow line-through text-slate-500 text-sm">{task.title}</div>
                <div className="flex gap-1">
                  <button onClick={() => restoreTask(task.id)} className="text-blue-600 hover:text-blue-800 text-xs px-2 py-1 bg-blue-100 rounded">Restore</button>
                  <button onClick={() => deleteTask(task.id)} className="text-red-600 hover:text-red-800 text-xs px-2 py-1 bg-red-100 rounded">Delete</button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {showDetails && selectedTask && (
        <TaskDetails task={selectedTask} onClose={() => setShowDetails(false)} urgencyColors={urgencyColors} importanceColors={importanceColors} getColorDot={getColorDot} />
      )}
    </div>
  );
}

function NewTaskForm({ onAdd, onCancel, colors, importanceColors }) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [urgency, setUrgency] = useState('red');
  const [importance, setImportance] = useState('red');

  const handleSubmit = () => {
    if (title.trim()) {
      onAdd(title, description, urgency, importance);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl p-6 w-full max-w-sm">
        <h2 className="text-xl font-bold mb-4">New Task</h2>
        <input
          type="text"
          placeholder="Task title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="w-full mb-3 px-3 py-2 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <textarea
          placeholder="Description (optional)"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          className="w-full mb-4 px-3 py-2 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none h-20"
        />
        <div className="mb-4">
          <label className="block text-sm font-semibold mb-2">Urgency</label>
          <select value={urgency} onChange={(e) => setUrgency(e.target.value)} className="w-full px-3 py-2 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500">
            {Object.entries(colors).map(([key, val]) => (
              <option key={key} value={key}>{val}</option>
            ))}
          </select>
        </div>
        <div className="mb-4">
          <label className="block text-sm font-semibold mb-2">Importance</label>
          <select value={importance} onChange={(e) => setImportance(e.target.value)} className="w-full px-3 py-2 border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500">
            {Object.entries(importanceColors).map(([key, val]) => (
              <option key={key} value={key}>{val}</option>
            ))}
          </select>
        </div>
        <div className="flex gap-2">
          <button onClick={handleSubmit} className="flex-1 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg font-semibold transition">Create</button>
          <button onClick={onCancel} className="flex-1 py-2 bg-slate-300 hover:bg-slate-400 text-slate-800 rounded-lg font-semibold transition">Cancel</button>
        </div>
      </div>
    </div>
  );
}

function TaskDetails({ task, onClose, urgencyColors, importanceColors, getColorDot }) {
  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl p-6 w-full max-w-sm">
        <h2 className="text-xl font-bold mb-4">{task.title}</h2>
        <div className="mb-4">
          <p className="text-sm font-semibold text-slate-600 mb-1">Description</p>
          <p className="text-slate-800">{task.description || 'No description'}</p>
        </div>
        <div className="mb-4 grid grid-cols-2 gap-4">
          <div>
            <p className="text-sm font-semibold text-slate-600 mb-1">Urgency</p>
            <div className="flex items-center gap-2">
              <span className={`inline-block w-3 h-3 rounded-full ${getColorDot(task.urgency)}`}></span>
              <p>{urgencyColors[task.urgency]}</p>
            </div>
          </div>
          <div>
            <p className="text-sm font-semibold text-slate-600 mb-1">Importance</p>
            <div className="flex items-center gap-2">
              <span className={`inline-block w-3 h-3 rounded-full ${getColorDot(task.importance)}`}></span>
              <p>{importanceColors[task.importance]}</p>
            </div>
          </div>
        </div>
        <button onClick={onClose} className="w-full py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg font-semibold transition">Close</button>
      </div>
    </div>
  );
}