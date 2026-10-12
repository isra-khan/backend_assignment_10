
// Store the marks of all students in an array
let student_marks = [45, 78, 92, 61, 88, 54, 73, 95];

// Increase every student's mark by 5
let updatedMarks = student_marks.map(marks => marks + 5);
console.log("Original marks:", student_marks);
console.log("Updated marks:", updatedMarks);

// Find all students who scored 70 or above
let seventyAboveMarks = student_marks.filter(marks => marks >= 70);
console.log("Marks 70 or above:", seventyAboveMarks);

// Find all students who scored more than 90
let nintyMarks = student_marks.filter(marks => marks > 90);
console.log("Marks above 90:", nintyMarks);

// Calculate the sum of all students' marks
let sumMarks = student_marks.reduce((sum, amount) => {
    return sum + amount;
}, 0);
console.log("Sum of marks is:", sumMarks);

// Display the original array again
console.log("Original marks remain unchanged:", student_marks);
