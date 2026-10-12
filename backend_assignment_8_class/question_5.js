
// Question 5 - Student Result Object

// Create the first student object
const marks = {
    name: "Isra",
    class: "2nd year",
    chemistrymarks: 55,
    mathematicsmarks: 50,
    urdumarks: 50,
    englishmarks: 60,

    // Method to calculate total marks and percentage
    calculate: function () {
        // Calculate the total marks obtained
        const totalMarks =
            this.chemistrymarks +
            this.mathematicsmarks +
            this.urdumarks +
            this.englishmarks;

        // Calculate percentage out of 400
        const percentage = (totalMarks / 400) * 100;

        // Return both total marks and percentage
        return {
            totalMarks: totalMarks,
            percentage: percentage
        };
    }
};

// Display the student's name and class using dot notation
console.log("Name:", marks.name);
console.log("Class:", marks.class);

// Access a property using bracket notation
console.log("Chemistry Marks:", marks["chemistrymarks"]);

// Call the method and store its result
const result1 = marks.calculate();

// Display the student's name, total marks, and percentage
console.log("Student:", marks.name);
console.log("Total Marks:", result1.totalMarks, "/ 400");
console.log("Percentage:", result1.percentage + "%");


// Create a second student object with the same type of method
const student2 = {
    name: "Ali",
    class: "2nd year",
    chemistrymarks: 80,
    mathematicsmarks: 75,
    urdumarks: 85,
    englishmarks: 90,

    // Reuse the same calculation logic
    calculate: marks.calculate
};

// Call the method for the second student
const result2 = student2.calculate();

// Display the second student's result
console.log("Student:", student2.name);
console.log("Total Marks:", result2.totalMarks, "/ 400");
console.log("Percentage:", result2.percentage + "%");


// Remove one property from the second student object
delete student2.urdumarks;

// Display the final second student object
console.log("Final Student Object:", student2);
