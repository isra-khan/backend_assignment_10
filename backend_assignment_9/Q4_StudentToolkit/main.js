// A school website has become difficult to maintain because all student-related code is written in one file. Separate the
// reusable student functions from the main page logic.
// Create these files: index.html, studentTools.js, and main.js.
// - In studentTools.js, create and make available a function that receives a student's first and last name and returns the
// full name.
// - In the same file, create and make available a function that receives marks from four subjects and returns the total
// marks.
// - Make one of these functions available as a named export and the other as the file's default export.
// - In main.js, bring both functions in from studentTools.js and use them with sample student data.
// - Display the full name and total marks in the console.
// - In index.html, load main.js correctly so the browser recognizes it as a module.
// - Run the page with a local development server and make sure both imported functions work.
import calculateMarks, { fullName } from './studentTools.js';

console.log(fullName("Isra", "Khan"));
console.log(calculateMarks(50, 60, 70, 80));